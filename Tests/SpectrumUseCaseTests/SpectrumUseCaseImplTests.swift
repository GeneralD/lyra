import Dependencies
import Domain
import Foundation
import Testing
import os

@testable import SpectrumUseCase

@Suite("SpectrumUseCaseImpl")
struct SpectrumUseCaseImplTests {
    @Test("startCapture forwards the pid to the repository")
    func startForwards() async {
        let harness = Harness()
        let started = await harness.useCase.startCapture(pid: 77)

        #expect(started == true)
        #expect(harness.repository.startedPids == [77])
    }

    @Test("stopCapture forwards to the repository")
    func stopForwards() async {
        let harness = Harness()
        await harness.useCase.stopCapture()

        #expect(harness.repository.stopCount == 1)
    }

    @Test("magnitudes converts the captured window into one value per bar")
    func magnitudesShape() {
        let harness = Harness(left: [Float](repeating: 0.5, count: 1024))
        let bins = harness.useCase.magnitudes(style: SpectrumStyle(barCount: 16, fftSize: 1024))

        #expect(bins.count == 16)
    }

    @Test("magnitudes is empty while nothing is captured")
    func magnitudesEmptyWithoutSamples() {
        let harness = Harness()

        #expect(harness.useCase.magnitudes(style: SpectrumStyle()).isEmpty)
    }

    // MARK: - stereo (#297)

    @Test("stereo mirrors the left channel and appends the right, bass in the center")
    func stereoMirrorsAroundCenter() throws {
        let style = SpectrumStyle(barCount: 16, fftSize: 1024)
        let leftOnly = Harness(left: sine(amplitude: 0.5), right: silence())
        let bins = leftOnly.useCase.magnitudes(style: style)

        // A left-only signal lights the left half and leaves the right dark…
        #expect(bins.count == 16)
        let leftPeak = try #require(bins.indices.max { bins[$0] < bins[$1] })
        #expect(leftPeak < 8)
        #expect(bins[leftPeak] > 0)
        #expect(bins[8...].allSatisfy { $0 < 0.001 })

        // …and swapping the channels lands the peak on the mirrored bar.
        let rightOnly = Harness(left: silence(), right: sine(amplitude: 0.5))
        let mirrored = rightOnly.useCase.magnitudes(style: style)
        let rightPeak = try #require(mirrored.indices.max { mirrored[$0] < mirrored[$1] })
        #expect(rightPeak == 15 - leftPeak)
        #expect(mirrored[..<8].allSatisfy { $0 < 0.001 })
    }

    @Test("mono averages both channels into one full-width row")
    func monoAveragesChannels() {
        let style = SpectrumStyle(stereo: false, barCount: 16, fftSize: 1024)
        let bins = Harness(left: sine(amplitude: 0.5), right: silence())
            .useCase.magnitudes(style: style)

        #expect(bins.count == 16)
        #expect((bins.max() ?? 0) > 0)

        // The average is channel-agnostic: swapping the channels yields the
        // identical row, unlike the stereo mirror.
        let swapped = Harness(left: silence(), right: sine(amplitude: 0.5))
            .useCase.magnitudes(style: style)
        #expect(bins == swapped)
    }

    // MARK: - un-gained output (#297)

    @Test("magnitudes are un-gained — halving the amplitude halves the bars")
    func magnitudesAreUngained() throws {
        // The gain (cava's autosens) lives in the Presenter now, so the
        // UseCase must preserve amplitude ratios rather than pin the peak:
        // the linear scale halves the bar when the input halves.
        let style = SpectrumStyle(barCount: 16, fftSize: 1024)
        let loud = try #require(
            Harness(left: sine(amplitude: 0.8))
                .useCase.magnitudes(style: style).max())
        let quiet = try #require(
            Harness(left: sine(amplitude: 0.4))
                .useCase.magnitudes(style: style).max())

        #expect(quiet > 0)
        #expect(abs(quiet / loud - 0.5) < 0.05)
    }
}

/// A sine on FFT bin 8 of a 1024-sample window, at the given amplitude.
private func sine(amplitude: Float, count: Int = 1024) -> [Float] {
    (0..<count).map { amplitude * sin(2 * .pi * 8 * Float($0) / 1024) }
}

private func silence(count: Int = 1024) -> [Float] {
    [Float](repeating: 0, count: count)
}

// MARK: - Harness

private struct Harness {
    let repository = FakeAudioCaptureRepository()
    let useCase: SpectrumUseCaseImpl

    /// Omitting `right` mirrors `left` into both channels.
    init(left: [Float] = [], right: [Float]? = nil) {
        repository.samples = StereoSamples(left: left, right: right ?? left)
        useCase = withDependencies { [repository] in
            $0.audioCaptureRepository = repository
        } operation: {
            SpectrumUseCaseImpl()
        }
    }
}

private final class FakeAudioCaptureRepository: AudioCaptureRepository, @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: (started: [Int](), stops: 0))
    var samples = StereoSamples()

    var startedPids: [Int] { state.withLock { $0.started } }
    var stopCount: Int { state.withLock { $0.stops } }

    func startCapture(pid: Int) async -> Bool {
        state.withLock { $0.started.append(pid) }
        return true
    }

    func stopCapture() async {
        state.withLock { $0.stops += 1 }
    }

    func latestSamples(count: Int) -> StereoSamples {
        samples.left.count >= count
            ? StereoSamples(
                left: Array(samples.left.suffix(count)),
                right: Array(samples.right.suffix(count)))
            : StereoSamples()
    }
}
