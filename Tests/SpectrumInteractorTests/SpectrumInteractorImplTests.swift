@preconcurrency import Combine
import Dependencies
import Domain
import Foundation
import Testing
import os

@testable import SpectrumInteractor

@Suite("SpectrumInteractorImpl")
struct SpectrumInteractorImplTests {
    @Test("playing source starts a capture for its pid and reports capturing")
    func playingStartsCapture() async {
        let harness = Harness()
        harness.interactor.start()
        harness.send(pid: 4242, playbackRate: 1)

        await harness.pollUntil { harness.spectrum.startedPids == [4242] }
        #expect(harness.spectrum.startedPids == [4242])
        await harness.pollUntil { harness.capturing.value == true }
        #expect(harness.capturing.value == true)
    }

    @Test("pausing stops the capture and reports not capturing")
    func pauseStopsCapture() async {
        let harness = Harness()
        harness.interactor.start()
        harness.send(pid: 4242, playbackRate: 1)
        await harness.pollUntil { harness.capturing.value == true }

        harness.send(pid: 4242, playbackRate: 0)
        await harness.pollUntil { harness.spectrum.stopCount > 0 }
        #expect(harness.spectrum.stopCount > 0)
        await harness.pollUntil { harness.capturing.value == false }
        #expect(harness.capturing.value == false)
    }

    @Test("app switch re-captures the new pid")
    func appSwitchRecaptures() async {
        let harness = Harness()
        harness.interactor.start()
        harness.send(pid: 1, playbackRate: 1)
        harness.send(pid: 2, playbackRate: 1)

        await harness.pollUntil { harness.spectrum.startedPids == [1, 2] }
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

        await harness.pollUntil { harness.spectrum.stopCount > 0 }
        #expect(harness.spectrum.startedPids == [4242])
    }

    @Test("vanished session stops the capture")
    func sessionGoneStopsCapture() async {
        let harness = Harness()
        harness.interactor.start()
        harness.send(pid: 4242, playbackRate: 1)
        await harness.pollUntil { harness.capturing.value == true }

        harness.sendSessionGone()
        await harness.pollUntil { harness.capturing.value == false }
        #expect(harness.capturing.value == false)
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
        await harness.pollUntil { harness.capturing.value == true }

        harness.interactor.stop()
        await harness.pollUntil { harness.spectrum.stopCount > 0 }
        #expect(harness.spectrum.stopCount > 0)
    }

    @Test("magnitudes forwards the configured style to the use case")
    func magnitudesForwards() {
        let harness = Harness()
        harness.spectrum.magnitudesResult = [0.25, 0.5]

        #expect(harness.interactor.magnitudes() == [0.25, 0.5])
        #expect(harness.spectrum.lastStyle?.barCount == 16)
    }

    @Test("magnitudes is empty while nothing is captured")
    func magnitudesEmptyWithoutCapture() {
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
    let spectrum = FakeSpectrumUseCase()
    let capturing = CurrentValueBox()
    let interactor: SpectrumInteractorImpl
    private let feed: AsyncStream<NowPlaying?>.Continuation
    private let cancellable: AnyCancellable

    init(enabled: Bool = true) {
        let style = SpectrumStyle(enabled: enabled, barCount: 16, fftSize: 1024)
        self.style = style
        let (stream, continuation) = AsyncStream<NowPlaying?>.makeStream()
        feed = continuation
        let interactor = withDependencies { [spectrum] in
            $0.configUseCase = StubConfigUseCase(appStyle: AppStyle(spectrum: style))
            $0.playbackUseCase = StubPlaybackUseCase(stream: stream)
            $0.spectrumUseCase = spectrum
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

private final class FakeSpectrumUseCase: SpectrumUseCase, @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(
        initialState: (started: [Int](), stops: 0, style: SpectrumStyle?.none))
    var magnitudesResult: [Float] = []

    var startedPids: [Int] { state.withLock { $0.started } }
    var stopCount: Int { state.withLock { $0.stops } }
    var lastStyle: SpectrumStyle? { state.withLock { $0.style } }

    func startCapture(pid: Int) async -> Bool {
        state.withLock { $0.started.append(pid) }
        return true
    }

    func stopCapture() async {
        state.withLock { $0.stops += 1 }
    }

    func magnitudes(style: SpectrumStyle) -> [Float] {
        state.withLock { $0.style = style }
        return magnitudesResult
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
