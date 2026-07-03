@preconcurrency import Combine
import Dependencies
import Domain
import Foundation
import Testing
import os

@testable import SpectrumInteractor

@Suite("SpectrumInteractorImpl")
struct SpectrumInteractorImplTests {
    @Test("playing source starts a tap for its pid and reports capturing")
    func playingStartsTap() async {
        let harness = Harness()
        harness.interactor.start()
        harness.send(pid: 4242, playbackRate: 1)

        await harness.pollUntil { harness.tap.startedPids == [4242] }
        #expect(harness.tap.startedPids == [4242])
        await harness.pollUntil { harness.capturing.value == true }
        #expect(harness.capturing.value == true)
    }

    @Test("pausing tears the tap down and reports not capturing")
    func pauseStopsTap() async {
        let harness = Harness()
        harness.interactor.start()
        harness.send(pid: 4242, playbackRate: 1)
        await harness.pollUntil { harness.capturing.value == true }

        harness.send(pid: 4242, playbackRate: 0)
        await harness.pollUntil { harness.tap.stopCount > 0 }
        #expect(harness.tap.stopCount > 0)
        await harness.pollUntil { harness.capturing.value == false }
        #expect(harness.capturing.value == false)
    }

    @Test("app switch re-taps the new pid")
    func appSwitchRetaps() async {
        let harness = Harness()
        harness.interactor.start()
        harness.send(pid: 1, playbackRate: 1)
        harness.send(pid: 2, playbackRate: 1)

        await harness.pollUntil { harness.tap.startedPids == [1, 2] }
        #expect(harness.tap.startedPids == [1, 2])
    }

    @Test("repeated identical events tap only once (periodic tick dedup)")
    func periodicTickDedup() async {
        let harness = Harness()
        harness.interactor.start()
        harness.send(pid: 4242, playbackRate: 1)
        harness.send(pid: 4242, playbackRate: 1)
        harness.send(pid: 4242, playbackRate: 1)

        await harness.pollUntil { harness.tap.startedPids == [4242] }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(harness.tap.startedPids == [4242])
    }

    @Test("vanished session tears the tap down")
    func sessionGoneStopsTap() async {
        let harness = Harness()
        harness.interactor.start()
        harness.send(pid: 4242, playbackRate: 1)
        await harness.pollUntil { harness.capturing.value == true }

        harness.sendSessionGone()
        await harness.pollUntil { harness.capturing.value == false }
        #expect(harness.capturing.value == false)
        #expect(harness.tap.stopCount > 0)
    }

    @Test("disabled spectrum never subscribes nor taps")
    func disabledIsInert() async {
        let harness = Harness(enabled: false)
        harness.interactor.start()
        harness.send(pid: 4242, playbackRate: 1)

        try? await Task.sleep(for: .milliseconds(50))
        #expect(harness.tap.startedPids.isEmpty)
    }

    @Test("stop tears down the active tap")
    func stopTearsDown() async {
        let harness = Harness()
        harness.interactor.start()
        harness.send(pid: 4242, playbackRate: 1)
        await harness.pollUntil { harness.capturing.value == true }

        harness.interactor.stop()
        await harness.pollUntil { harness.tap.stopCount > 0 }
        #expect(harness.tap.stopCount > 0)
    }

    @Test("magnitudes converts the captured window into one value per bar")
    func magnitudesShape() {
        let harness = Harness(samples: [Float](repeating: 0.5, count: 1024))
        let bins = harness.interactor.magnitudes()
        #expect(bins.count == harness.style.barCount)
    }

    @Test("magnitudes is empty while nothing is captured")
    func magnitudesEmptyWithoutSamples() {
        let harness = Harness()
        #expect(harness.interactor.magnitudes().isEmpty)
    }
}

// MARK: - Harness

/// Builds a `SpectrumInteractorImpl` whose dependencies are all fakes, and
/// keeps the fakes accessible for assertions. Now-playing events are fed
/// through the stubbed `PlaybackUseCase` stream, mirroring the live wiring
/// where the interactor consumes the repository's multicast stream directly.
private struct Harness {
    let style: SpectrumStyle
    let tap = FakeAudioTapDataSource()
    let capturing = CurrentValueBox()
    let interactor: SpectrumInteractorImpl
    private let feed: AsyncStream<NowPlaying?>.Continuation
    private let cancellable: AnyCancellable

    init(enabled: Bool = true, samples: [Float] = []) {
        let style = SpectrumStyle(enabled: enabled, barCount: 16, fftSize: 1024)
        self.style = style
        tap.samples = samples
        let (stream, continuation) = AsyncStream<NowPlaying?>.makeStream()
        feed = continuation
        let interactor = withDependencies { [tap] in
            $0.configUseCase = StubConfigUseCase(appStyle: AppStyle(spectrum: style))
            $0.playbackUseCase = StubPlaybackUseCase(stream: stream)
            $0.audioTapDataSource = tap
        } operation: {
            SpectrumInteractorImpl()
        }
        self.interactor = interactor
        self.cancellable = interactor.isCapturing.sink { [capturing] in capturing.value = $0 }
    }

    func send(pid: Int?, playbackRate: Double) {
        feed.yield(
            NowPlaying(
                title: nil, artist: nil, artworkData: nil, duration: nil,
                rawElapsed: nil, playbackRate: playbackRate, timestamp: nil, pid: pid))
    }

    func sendSessionGone() {
        feed.yield(nil)
    }

    func pollUntil(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

private final class CurrentValueBox: @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: false)
    var value: Bool {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }
}

private final class FakeAudioTapDataSource: AudioTapDataSource, @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: (started: [Int](), stops: 0))
    var samples: [Float] = []

    var startedPids: [Int] { state.withLock { $0.started } }
    var stopCount: Int { state.withLock { $0.stops } }

    func startTap(pid: Int) async -> Bool {
        state.withLock { $0.started.append(pid) }
        return true
    }

    func stopTap() async {
        state.withLock { $0.stops += 1 }
    }

    func latestSamples(count: Int) -> [Float] {
        samples.count >= count ? Array(samples.suffix(count)) : []
    }
}

private struct StubConfigUseCase: ConfigUseCase {
    let appStyle: AppStyle
    func template(format: ConfigFormat) -> String? { nil }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { "" }
    var existingConfigPath: String? { nil }
}

private struct StubPlaybackUseCase: PlaybackUseCase {
    let stream: AsyncStream<NowPlaying?>
    func fetchNowPlaying() async -> NowPlaying? { nil }
    func observeNowPlaying() -> AsyncStream<NowPlaying?> { stream }
    func elapsedTime(for nowPlaying: NowPlaying) -> TimeInterval? { nil }
}
