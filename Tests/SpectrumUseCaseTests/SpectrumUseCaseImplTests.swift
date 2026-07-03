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
        let harness = Harness(samples: [Float](repeating: 0.5, count: 1024))
        let bins = harness.useCase.magnitudes(style: SpectrumStyle(barCount: 16, fftSize: 1024))

        #expect(bins.count == 16)
    }

    @Test("magnitudes is empty while nothing is captured")
    func magnitudesEmptyWithoutSamples() {
        let harness = Harness()

        #expect(harness.useCase.magnitudes(style: SpectrumStyle()).isEmpty)
    }
}

// MARK: - Harness

private struct Harness {
    let repository = FakeAudioCaptureRepository()
    let useCase: SpectrumUseCaseImpl

    init(samples: [Float] = []) {
        repository.samples = samples
        useCase = withDependencies { [repository] in
            $0.audioCaptureRepository = repository
        } operation: {
            SpectrumUseCaseImpl()
        }
    }
}

private final class FakeAudioCaptureRepository: AudioCaptureRepository, @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: (started: [Int](), stops: 0))
    var samples: [Float] = []

    var startedPids: [Int] { state.withLock { $0.started } }
    var stopCount: Int { state.withLock { $0.stops } }

    func startCapture(pid: Int) async -> Bool {
        state.withLock { $0.started.append(pid) }
        return true
    }

    func stopCapture() async {
        state.withLock { $0.stops += 1 }
    }

    func latestSamples(count: Int) -> [Float] {
        samples.count >= count ? Array(samples.suffix(count)) : []
    }
}
