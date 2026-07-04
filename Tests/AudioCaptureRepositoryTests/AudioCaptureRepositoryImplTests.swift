import Dependencies
import Domain
import Foundation
import Testing
import os

@testable import AudioCaptureRepository

@Suite("AudioCaptureRepositoryImpl")
struct AudioCaptureRepositoryImplTests {
    @Test("startCapture forwards the pid and returns the datasource result")
    func startForwards() async {
        let harness = Harness()
        let started = await harness.repository.startCapture(pid: 42)

        #expect(started == true)
        #expect(harness.dataSource.startedPids == [42])
    }

    @Test("stopCapture forwards to the datasource")
    func stopForwards() async {
        let harness = Harness()
        await harness.repository.stopCapture()

        #expect(harness.dataSource.stopCount == 1)
    }

    @Test("latestSamples forwards the requested count per channel")
    func latestSamplesForwards() {
        let harness = Harness(samples: StereoSamples(left: [1, 2, 3, 4], right: [5, 6, 7, 8]))
        let samples = harness.repository.latestSamples(count: 2)

        #expect(samples == StereoSamples(left: [3, 4], right: [7, 8]))
    }
}

// MARK: - Harness

private struct Harness {
    let dataSource = FakeAudioTapDataSource()
    let repository: AudioCaptureRepositoryImpl

    init(samples: StereoSamples = StereoSamples()) {
        dataSource.samples = samples
        repository = withDependencies { [dataSource] in
            $0.audioTapDataSource = dataSource
        } operation: {
            AudioCaptureRepositoryImpl()
        }
    }
}

private final class FakeAudioTapDataSource: AudioTapDataSource, @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: (started: [Int](), stops: 0))
    var samples = StereoSamples()

    var startedPids: [Int] { state.withLock { $0.started } }
    var stopCount: Int { state.withLock { $0.stops } }

    func startTap(pid: Int) async -> Bool {
        state.withLock { $0.started.append(pid) }
        return true
    }

    func stopTap() async {
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
