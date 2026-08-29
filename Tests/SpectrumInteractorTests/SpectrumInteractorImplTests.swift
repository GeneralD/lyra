@preconcurrency import Combine
import Dependencies
import Domain
import Foundation
import TestSupport
import Testing
import os

@testable import SpectrumInteractor

@Suite("SpectrumInteractorImpl", .timeLimit(.minutes(1)))
struct SpectrumInteractorImplTests {
    @Test("playing source starts a capture for its pid and reports capturing")
    func playingStartsCapture() async {
        let harness = Harness()
        harness.interactor.start()
        harness.send(pid: 4242, playbackRate: 1)

        await harness.spectrum.starts.settle { $0 == [4242] }
        #expect(harness.spectrum.startedPids == [4242])
        await harness.capturing.settle { $0.last == true }
        #expect(harness.capturing.last == true)
    }

    @Test("pausing stops the capture and reports not capturing")
    func pauseStopsCapture() async {
        let harness = Harness()
        harness.interactor.start()
        harness.send(pid: 4242, playbackRate: 1)
        await harness.capturing.settle { $0.last == true }

        harness.send(pid: 4242, playbackRate: 0)
        await harness.spectrum.stops.waitForCount(1)
        #expect(harness.spectrum.stopCount > 0)
        await harness.capturing.settle { $0.last == false }
        #expect(harness.capturing.last == false)
    }

    @Test("app switch re-captures the new pid")
    func appSwitchRecaptures() async {
        let harness = Harness()
        harness.interactor.start()
        harness.send(pid: 1, playbackRate: 1)
        harness.send(pid: 2, playbackRate: 1)

        await harness.spectrum.starts.settle { $0 == [1, 2] }
        #expect(harness.spectrum.startedPids == [1, 2])
    }

    @Test("repeated identical events capture only once (periodic tick dedup)")
    func periodicTickDedup() async {
        let harness = Harness()
        harness.interactor.start()
        harness.send(pid: 4242, playbackRate: 1)
        harness.send(pid: 4242, playbackRate: 1)
        harness.send(pid: 4242, playbackRate: 1)
        // The pause marker is processed strictly after the three identical
        // events (single serial consumer), so once it lands every duplicate
        // has been evaluated — no fixed sleep needed.
        harness.send(pid: 4242, playbackRate: 0)

        await harness.spectrum.stops.waitForCount(1)
        #expect(harness.spectrum.startedPids == [4242])
    }

    @Test("vanished session stops the capture")
    func sessionGoneStopsCapture() async {
        let harness = Harness()
        harness.interactor.start()
        harness.send(pid: 4242, playbackRate: 1)
        await harness.capturing.settle { $0.last == true }

        harness.sendSessionGone()
        await harness.capturing.settle { $0.last == false }
        #expect(harness.capturing.last == false)
        #expect(harness.spectrum.stopCount > 0)
    }

    @Test("disabled spectrum never subscribes nor captures")
    func disabledIsInert() {
        let harness = Harness(enabled: false)
        harness.interactor.start()
        harness.send(pid: 4242, playbackRate: 1)

        // Disabled start() returns before any task exists, so nothing can
        // consume the event — the assertion is safe immediately.
        #expect(harness.spectrum.startedPids.isEmpty)
    }

    @Test("stop tears down the active capture")
    func stopTearsDown() async {
        let harness = Harness()
        harness.interactor.start()
        harness.send(pid: 4242, playbackRate: 1)
        await harness.capturing.settle { $0.last == true }

        harness.interactor.stop()
        await harness.spectrum.stops.waitForCount(1)
        #expect(harness.spectrum.stopCount > 0)
    }

    @Test("same-source ticks never rebuild the tap")
    func sameSourceDoesNotRebuildTap() async {
        let harness = Harness()
        harness.interactor.start()
        harness.send(pid: 4242, playbackRate: 1, title: "Song A")
        await harness.capturing.settle { $0.last == true }

        // The helper re-emits the same pid+playing state every few seconds
        // (and on track change, which the interactor no longer inspects):
        // the AudioSourceState dedup must swallow it so the tap is not
        // torn down and rebuilt.
        harness.send(pid: 4242, playbackRate: 1, title: "Song B")
        harness.send(pid: 4242, playbackRate: 1, title: "Song B")
        // Land a pause so the play events above were fully evaluated.
        harness.send(pid: 4242, playbackRate: 0)
        await harness.spectrum.stops.waitForCount(1)
        #expect(harness.spectrum.startedPids == [4242])
    }

    @Test("a failed capture is retried on the next identical now-playing tick (#312)")
    func failedCaptureRetriesOnNextTick() async {
        let harness = Harness()
        // First tap creation fails (transient app-switch race), the retry
        // succeeds. The failure leaves the retry budget open, so an identical
        // repeat is let back through the dedup instead of being swallowed.
        harness.spectrum.startResults = [false, true]
        harness.interactor.start()
        harness.send(pid: 4242, playbackRate: 1)
        // The helper re-emits the same pid+playing state on its periodic tick.
        // Pre-fix, a repeat was unconditionally swallowed by the dedup, so a
        // failed start could never recover until a daemon restart; the retry
        // budget now lets this identical event back through to re-attempt.
        harness.send(pid: 4242, playbackRate: 1)

        await harness.spectrum.starts.settle { $0 == [4242, 4242] }
        #expect(harness.spectrum.startedPids == [4242, 4242])
        await harness.capturing.settle { $0.last == true }
        #expect(harness.capturing.last == true)
    }

    @Test("retries are bounded so a permanent failure does not spin forever (#312)")
    func failedCaptureGivesUpAfterBoundedRetries() async {
        let harness = Harness()
        // A permanent failure (old OS / TCC denial) never succeeds.
        harness.spectrum.startResults = Array(repeating: false, count: 8)
        harness.interactor.start()
        // Five identical ticks, but the source is retried at most 3 times
        // (maxCaptureAttempts) before the dedup gives up until the source
        // changes — so a denied capture cannot log/hit CoreAudio every tick.
        for _ in 0..<5 { harness.send(pid: 4242, playbackRate: 1) }
        // The pause is a new source: it lands strictly after the five identical
        // ticks were evaluated and marks the end of the retry window.
        harness.send(pid: 4242, playbackRate: 0)

        await harness.spectrum.stops.waitForCount(1)
        #expect(harness.spectrum.startedPids == [4242, 4242, 4242])
        // stopCapture() runs before subject.send(false) inside the same pause
        // branch, but nothing guarantees the interactor's task resumes onto
        // that next line before this task observes the stop — wait for
        // capturing itself rather than trusting in-task ordering across tasks.
        await harness.capturing.settle { $0.last == false }
        #expect(harness.capturing.last == false)
    }

    @Test("second start() while running never spawns a competing processor")
    func startTwiceKeepsSingleProcessor() async {
        let harness = Harness()
        harness.interactor.start()
        harness.interactor.start()
        harness.send(pid: 4242, playbackRate: 1)
        // Pause marker: once it lands, the play event was fully evaluated
        // by however many processors exist — a competing second processor
        // would have doubled the capture start.
        harness.send(pid: 4242, playbackRate: 0)

        await harness.spectrum.stops.waitForCount(1)
        #expect(harness.spectrum.startedPids == [4242])
    }

    @Test("stop then start captures again for the new session")
    func restartAfterStopCapturesAgain() async {
        let harness = Harness()
        harness.interactor.start()
        harness.send(pid: 4242, playbackRate: 1)
        await harness.capturing.settle { $0.last == true }

        harness.interactor.stop()
        harness.interactor.start()
        // The new processor replays the history and re-captures; the stale
        // teardown from stop() must not destroy the new capture.
        await harness.spectrum.starts.settle { $0.count == 2 }
        #expect(harness.spectrum.startedPids == [4242, 4242])
        await harness.capturing.settle { $0.last == true }
        #expect(harness.capturing.last == true)
    }

    @Test("magnitudes forwards the configured style and bar count to the use case")
    func magnitudesForwards() {
        let harness = Harness()
        harness.spectrum.magnitudesResult = [0.25, 0.5]

        #expect(harness.interactor.magnitudes(barCount: 16) == [0.25, 0.5])
        #expect(harness.spectrum.lastStyle?.fftSize == 1024)
        #expect(harness.spectrum.lastBarCount == 16)
    }

    @Test("magnitudes is empty while nothing is captured")
    func magnitudesEmptyWithoutCapture() {
        let harness = Harness()
        #expect(harness.interactor.magnitudes(barCount: 16).isEmpty)
    }
}

// MARK: - Harness

/// Builds a `SpectrumInteractorImpl` whose dependencies are all fakes, and
/// keeps the fakes accessible for assertions. Now-playing events are fed
/// through the stubbed `PlaybackUseCase` stream, mirroring the live wiring
/// where the interactor consumes the repository's multicast stream directly.
private struct Harness {
    let style: SpectrumStyle
    let spectrum = FakeSpectrumUseCase()
    let playback = StubPlaybackUseCase()
    let capturing = Collector<Bool>()
    let interactor: SpectrumInteractorImpl
    private let cancellable: AnyCancellable

    init(enabled: Bool = true) {
        let style = SpectrumStyle(enabled: enabled, fftSize: 1024)
        self.style = style
        let interactor = withDependencies { [spectrum, playback] in
            $0.configUseCase = StubConfigUseCase(appStyle: AppStyle(spectrum: style))
            $0.playbackUseCase = playback
            $0.spectrumUseCase = spectrum
        } operation: {
            SpectrumInteractorImpl()
        }
        self.interactor = interactor
        self.cancellable = interactor.isCapturing.sink { [capturing] in capturing.append($0) }
    }

    func send(pid: Int?, playbackRate: Double, title: String? = nil) {
        playback.send(
            NowPlaying(
                title: title, artist: nil, artworkData: nil, duration: nil,
                rawElapsed: nil, playbackRate: playbackRate, timestamp: nil, pid: pid))
    }

    func sendSessionGone() {
        playback.send(nil)
    }
}

private final class FakeSpectrumUseCase: SpectrumUseCase, @unchecked Sendable {
    /// pids passed to successive `startCapture` calls, in call order.
    let starts = Collector<Int>()
    /// One entry per `stopCapture` call.
    let stops = Collector<Void>()

    private let state = OSAllocatedUnfairLock(
        initialState: (style: SpectrumStyle?.none, bars: Int?.none, results: [Bool]()))
    var magnitudesResult: [Float] = []

    var startedPids: [Int] { starts.values }
    var stopCount: Int { stops.count }
    var lastStyle: SpectrumStyle? { state.withLock { $0.style } }
    var lastBarCount: Int? { state.withLock { $0.bars } }

    /// Scripted return values for successive `startCapture` calls, consumed in
    /// order; once exhausted the capture succeeds. Default empty → always
    /// succeeds, keeping the happy-path tests unchanged.
    var startResults: [Bool] {
        get { state.withLock { $0.results } }
        set { state.withLock { $0.results = newValue } }
    }

    func startCapture(pid: Int) async -> Bool {
        starts.append(pid)
        return state.withLock {
            guard !$0.results.isEmpty else { return true }
            return $0.results.removeFirst()
        }
    }

    func stopCapture() async {
        stops.append(())
    }

    func magnitudes(style: SpectrumStyle, barCount: Int) -> [Float] {
        state.withLock {
            $0.style = style
            $0.bars = barCount
        }
        return magnitudesResult
    }
}

private struct StubConfigUseCase: ConfigUseCase {
    let appStyle: AppStyle
    func reload() -> ConfigReloadOutcome { .updated(appStyle) }
    func template(format: ConfigFormat) -> String? { nil }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { "" }
    var existingConfigPath: String? { nil }
}

/// Multicast playback stub mirroring the live repository: every
/// `observeNowPlaying()` call gets its own stream, events fan out to all
/// subscribers, and history replays to late subscribers so events sent
/// before the processor task registers are never lost.
private final class StubPlaybackUseCase: PlaybackUseCase, @unchecked Sendable {
    private struct State {
        var subscribers: [AsyncStream<NowPlaying?>.Continuation] = []
        var history: [NowPlaying?] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func fetchNowPlaying() async -> NowPlaying? { nil }

    func observeNowPlaying() -> AsyncStream<NowPlaying?> {
        AsyncStream { continuation in
            state.withLock { state in
                for value in state.history { continuation.yield(value) }
                state.subscribers.append(continuation)
            }
        }
    }

    func elapsedTime(for nowPlaying: NowPlaying) -> TimeInterval? { nil }

    func send(_ value: NowPlaying?) {
        let subscribers = state.withLock { state -> [AsyncStream<NowPlaying?>.Continuation] in
            state.history.append(value)
            return state.subscribers
        }
        for subscriber in subscribers { subscriber.yield(value) }
    }
}
