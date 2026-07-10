import Dependencies
import Domain
import Foundation
import FrequencyAnalyzer
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
        let bins = harness.useCase.magnitudes(
            style: SpectrumStyle(fftSize: 1024), barCount: 16)

        #expect(bins.count == 16)
    }

    @Test("magnitudes is empty while nothing is captured")
    func magnitudesEmptyWithoutSamples() {
        let harness = Harness()

        #expect(harness.useCase.magnitudes(style: SpectrumStyle(), barCount: 16).isEmpty)
    }

    @Test("magnitudes is empty when the derived bar count is zero")
    func magnitudesEmptyForZeroBars() {
        let harness = Harness(left: [Float](repeating: 0.5, count: 1024))

        #expect(harness.useCase.magnitudes(style: SpectrumStyle(fftSize: 1024), barCount: 0).isEmpty)
    }

    @Test("the analyzer follows the bar count as the width changes")
    func magnitudesFollowsBarCount() {
        let harness = Harness(left: [Float](repeating: 0.5, count: 1024))
        let style = SpectrumStyle(stereo: false, fftSize: 1024)

        #expect(harness.useCase.magnitudes(style: style, barCount: 24).count == 24)
        // A resize asks for a different count; the analyzer rebuilds for it.
        #expect(harness.useCase.magnitudes(style: style, barCount: 40).count == 40)
    }

    // MARK: - stereo (#297)

    @Test("stereo mirrors the left channel and appends the right, bass in the center")
    func stereoMirrorsAroundCenter() throws {
        let style = SpectrumStyle(fftSize: 1024)
        let leftOnly = Harness(left: sine(amplitude: 0.5), right: silence())
        let bins = leftOnly.useCase.magnitudes(style: style, barCount: 16)

        // A left-only signal lights the left half and leaves the right dark…
        #expect(bins.count == 16)
        let leftPeak = try #require(bins.indices.max { bins[$0] < bins[$1] })
        #expect(leftPeak < 8)
        #expect(bins[leftPeak] > 0)
        #expect(bins[8...].allSatisfy { $0 < 0.001 })

        // …and swapping the channels lands the peak on the mirrored bar.
        let rightOnly = Harness(left: silence(), right: sine(amplitude: 0.5))
        let mirrored = rightOnly.useCase.magnitudes(style: style, barCount: 16)
        let rightPeak = try #require(mirrored.indices.max { mirrored[$0] < mirrored[$1] })
        #expect(rightPeak == 15 - leftPeak)
        #expect(mirrored[..<8].allSatisfy { $0 < 0.001 })
    }

    @Test("mono averages both channels into one full-width row")
    func monoAveragesChannels() {
        let style = SpectrumStyle(stereo: false, fftSize: 1024)
        let bins = Harness(left: sine(amplitude: 0.5), right: silence())
            .useCase.magnitudes(style: style, barCount: 16)

        #expect(bins.count == 16)
        #expect((bins.max() ?? 0) > 0)

        // The average is channel-agnostic: swapping the channels yields the
        // identical row, unlike the stereo mirror.
        let swapped = Harness(left: silence(), right: sine(amplitude: 0.5))
            .useCase.magnitudes(style: style, barCount: 16)
        #expect(bins == swapped)
    }

    // MARK: - un-gained output (#297)

    @Test("magnitudes are un-gained — halving the amplitude halves the bars")
    func magnitudesAreUngained() throws {
        // The gain (cava's autosens) lives in the Presenter now, so the
        // UseCase must preserve amplitude ratios rather than pin the peak:
        // the linear scale halves the bar when the input halves.
        let style = SpectrumStyle(fftSize: 1024)
        let loud = try #require(
            Harness(left: sine(amplitude: 0.8))
                .useCase.magnitudes(style: style, barCount: 16).max())
        let quiet = try #require(
            Harness(left: sine(amplitude: 0.4))
                .useCase.magnitudes(style: style, barCount: 16).max())

        #expect(quiet > 0)
        #expect(abs(quiet / loud - 0.5) < 0.05)
    }

    // MARK: - analyzer memoization

    @Test("the analyzer is reused when both bar count and sample rate are unchanged")
    func analyzerCachedOnMatchingKey() {
        // Two calls on the *same* use-case instance with identical bar count
        // and sample rate must return the same magnitudes — the analyzer is
        // built once and reused (cache-hit path of resolvedAnalyzer).
        let pcm = sine(amplitude: 0.5)
        let style = SpectrumStyle(stereo: false, fftSize: 1024)
        let harness = Harness(left: pcm, sampleRate: 48000)

        let first = harness.useCase.magnitudes(style: style, barCount: 24)
        let second = harness.useCase.magnitudes(style: style, barCount: 24)

        #expect(first == second)
    }

    @Test("the analyzer rebuilds when the tap sample rate changes on the same instance")
    func analyzerRebuildsOnSampleRateChange() {
        // On a source switch the tap is torn down and recreated at the new
        // device's rate; the same use-case instance sees a different sampleRate
        // from latestSamples and must rebuild the FrequencyAnalyzer (whose
        // Hz→bin mapping depends on the rate).
        let pcm = sine(amplitude: 0.5)
        let style = SpectrumStyle(stereo: false, fftSize: 1024)
        let harness = Harness(left: pcm, sampleRate: 48000)

        let at48k = harness.useCase.magnitudes(style: style, barCount: 24)

        // Simulate a rate change on the same use-case (same bar count, new rate).
        harness.repository.samples = StereoSamples(left: pcm, right: pcm, sampleRate: 44100)
        let at44k = harness.useCase.magnitudes(style: style, barCount: 24)

        #expect(at48k != at44k)
    }

    // MARK: - sample-rate propagation (#299)

    @Test("the tap sample rate reaches the analyzer — same PCM, different rate, different bands")
    func magnitudesFollowSampleRate() {
        // The band cutoffs are Hz→bin mapped with the tap rate, so the same
        // captured window grouped for 48 kHz vs 96 kHz yields different bars.
        // A hardcoded rate would make these identical.
        let pcm = sine(amplitude: 0.5)
        let style = SpectrumStyle(stereo: false, fftSize: 1024)
        let at48k = Harness(left: pcm, sampleRate: 48000).useCase.magnitudes(style: style, barCount: 24)
        let at96k = Harness(left: pcm, sampleRate: 96000).useCase.magnitudes(style: style, barCount: 24)

        #expect(at48k != at96k)
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

    /// Omitting `right` mirrors `left` into both channels. `sampleRate` is the
    /// tap rate the fake tags its window with (#299).
    init(left: [Float] = [], right: [Float]? = nil, sampleRate: Double = 48000) {
        repository.samples = StereoSamples(left: left, right: right ?? left, sampleRate: sampleRate)
        useCase = withDependencies { [repository] in
            $0.audioCaptureRepository = repository
            $0.frequencyAnalyzerFactory = LiveFrequencyAnalyzerFactory()
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
                right: Array(samples.right.suffix(count)),
                sampleRate: samples.sampleRate)
            : StereoSamples()
    }
}
