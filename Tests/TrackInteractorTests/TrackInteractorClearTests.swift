@preconcurrency import Combine
import Dependencies
import Domain
import Foundation
import TestSupport
import Testing

@testable import TrackInteractor

// MARK: - Stubs

private final class StubPlaybackUseCase: PlaybackUseCase, @unchecked Sendable {
    let subject = CurrentValueSubject<NowPlaying?, Never>(nil)

    func fetchNowPlaying() async -> NowPlaying? { nil }

    func observeNowPlaying() -> AsyncStream<NowPlaying?> {
        AsyncStream { continuation in
            let cancellable = subject.sink(
                receiveCompletion: { _ in continuation.finish() },
                receiveValue: { continuation.yield($0) }
            )
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    func elapsedTime(for np: NowPlaying) -> TimeInterval? { np.rawElapsed }
}

private struct InstantMetadataUseCase: MetadataUseCase, Sendable {
    func resolve(track: Track) async -> Track? { nil }
    func resolveCandidates(track: Track) async -> [Track] { [] }
    func isAIMetadataCached(track: Track) async -> Bool { true }
}

private struct StubLyricsUseCase: LyricsUseCase, Sendable {
    func fetchLyrics(track: Track) async -> LyricsResult {
        LyricsResult(trackName: track.title, artistName: track.artist, syncedLyrics: "[\(track.title)]")
    }

    func fetchLyrics(candidates: [Track]) async -> LyricsResult {
        guard let first = candidates.first else { return LyricsResult() }
        return await fetchLyrics(track: first)
    }

    func parseLyricsContent(from result: LyricsResult?) -> LyricsContent? {
        guard let synced = result?.syncedLyrics, !synced.isEmpty else { return nil }
        return .timed([LyricLine(time: 0, text: synced)])
    }
}

private struct StubConfigUseCase: ConfigUseCase, Sendable {
    var appStyle: AppStyle { .init() }
    func reload() -> ConfigReloadOutcome { .updated(appStyle) }
    func template(format: ConfigFormat) -> String? { nil }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { "" }
    var existingConfigPath: String? { nil }
}

// MARK: - Helpers

private func makeInteractor(
    playback: StubPlaybackUseCase,
    clock: TestClock<Duration>
) -> TrackInteractorImpl {
    withDependencies {
        $0.continuousClock = clock
        $0.playbackUseCase = playback
        $0.metadataUseCase = InstantMetadataUseCase()
        $0.lyricsUseCase = StubLyricsUseCase()
        $0.configUseCase = StubConfigUseCase()
    } operation: {
        TrackInteractorImpl()
    }
}

private func nowPlaying(
    title: String?,
    artist: String?,
    artworkData: Data? = nil,
    playbackRate: Double = 1
) -> NowPlaying {
    NowPlaying(
        title: title, artist: artist, artworkData: artworkData,
        duration: nil, rawElapsed: nil, playbackRate: playbackRate, timestamp: nil)
}

// MARK: - Tests

@Suite("TrackInteractor source-gone clear", .serialized, .timeLimit(.minutes(1)))
struct TrackInteractorClearTests {

    @Test("nil NowPlaying persisting past the grace emits one .idle clear update")
    func sustainedNilClearsDisplay() async throws {
        let playback = StubPlaybackUseCase()
        let clock = TestClock<Duration>()
        let interactor = makeInteractor(playback: playback, clock: clock)

        let collector = Collector<TrackUpdate>()
        let cancellable = interactor.trackChange.sink { collector.append($0) }
        defer { cancellable.cancel() }

        playback.subject.send(nowPlaying(title: "Track A", artist: "Artist A"))
        await clock.advance(by: .milliseconds(300))
        _ = await collector.waitFor { $0.title == "Track A" && $0.lyricsState == .resolved }

        playback.subject.send(nil)

        // Inside the grace window nothing clears.
        await clock.advance(by: .seconds(4))
        #expect(!collector.contains { $0.lyricsState == .idle }, "grace has not elapsed")

        await clock.advance(by: .seconds(2))
        let idle = try #require(await collector.waitFor { $0.lyricsState == .idle })
        #expect(idle.title == nil && idle.artist == nil && idle.lyrics == nil)

        // The clear fires once per source-gone run, not per nil event.
        playback.subject.send(nil)
        playback.subject.send(nil)
        await clock.advance(by: .seconds(10))
        #expect(collector.values.filter { $0.lyricsState == .idle }.count == 1)
    }

    @Test("nil recovering inside the grace emits no clear")
    func transientNilKeepsDisplay() async throws {
        let playback = StubPlaybackUseCase()
        let clock = TestClock<Duration>()
        let interactor = makeInteractor(playback: playback, clock: clock)

        let collector = Collector<TrackUpdate>()
        let cancellable = interactor.trackChange.sink { collector.append($0) }
        defer { cancellable.cancel() }

        playback.subject.send(nowPlaying(title: "Track A", artist: "Artist A"))
        await clock.advance(by: .milliseconds(300))
        _ = await collector.waitFor { $0.lyricsState == .resolved }

        playback.subject.send(nil)
        await clock.advance(by: .seconds(3))

        playback.subject.send(nowPlaying(title: "Track B", artist: "Artist B"))
        await clock.advance(by: .seconds(10))
        _ = await collector.waitFor { $0.title == "Track B" && $0.lyricsState == .resolved }

        #expect(!collector.contains { $0.lyricsState == .idle }, "recovered before grace elapsed")
    }

    @Test("same track returning after a clear re-resolves")
    func resumedTrackResolvesAgain() async throws {
        let playback = StubPlaybackUseCase()
        let clock = TestClock<Duration>()
        let interactor = makeInteractor(playback: playback, clock: clock)

        let collector = Collector<TrackUpdate>()
        let cancellable = interactor.trackChange.sink { collector.append($0) }
        defer { cancellable.cancel() }

        playback.subject.send(nowPlaying(title: "Track A", artist: "Artist A"))
        await clock.advance(by: .milliseconds(300))
        _ = await collector.waitFor { $0.lyricsState == .resolved }

        playback.subject.send(nil)
        await clock.advance(by: .seconds(6))
        _ = await collector.waitFor { $0.lyricsState == .idle }

        playback.subject.send(nowPlaying(title: "Track A", artist: "Artist A"))
        await clock.advance(by: .milliseconds(300))
        // The second resolve is async past the debounce — wait on the
        // collector itself rather than reading values on a timing guess.
        await collector.settle {
            $0.filter { $0.title == "Track A" && $0.lyricsState == .resolved }.count >= 2
        }
        #expect(
            collector.values.filter { $0.title == "Track A" && $0.lyricsState == .resolved }.count
                == 2,
            "the nil boundary must break dedup so the same track re-resolves")
    }

    @Test("artwork emits nil when the clear fires")
    func artworkClears() async throws {
        let playback = StubPlaybackUseCase()
        let clock = TestClock<Duration>()
        let interactor = makeInteractor(playback: playback, clock: clock)

        let collector = Collector<Data?>()
        let cancellable = interactor.artwork.sink { collector.append($0) }
        defer { cancellable.cancel() }

        playback.subject.send(
            nowPlaying(title: "Track A", artist: "Artist A", artworkData: Data([1, 2, 3])))
        _ = await collector.waitFor { $0 == Data([1, 2, 3]) }

        playback.subject.send(nil)
        await clock.advance(by: .seconds(6))

        _ = try #require(await collector.waitFor { $0 == nil })
    }

    @Test("artist-drop events (mute) never trigger a clear")
    func mutedArtistStaysDisplayed() async throws {
        let playback = StubPlaybackUseCase()
        let clock = TestClock<Duration>()
        let interactor = makeInteractor(playback: playback, clock: clock)

        let collector = Collector<TrackUpdate>()
        let cancellable = interactor.trackChange.sink { collector.append($0) }
        defer { cancellable.cancel() }

        playback.subject.send(nowPlaying(title: "Track A", artist: "Artist A"))
        await clock.advance(by: .milliseconds(300))
        _ = await collector.waitFor { $0.lyricsState == .resolved }

        // Muted-style report: same title, artist newly empty — swallowed,
        // not a nil boundary, so no grace is ever armed.
        playback.subject.send(nowPlaying(title: "Track A", artist: ""))
        playback.subject.send(nowPlaying(title: "Track A", artist: ""))
        await clock.advance(by: .seconds(30))

        #expect(!collector.contains { $0.lyricsState == .idle }, "suppressed events are not a clear boundary")
    }

    @Test("a suppressed report inside the grace cancels the pending clear")
    func suppressedCancelsGrace() async throws {
        let playback = StubPlaybackUseCase()
        let clock = TestClock<Duration>()
        let interactor = makeInteractor(playback: playback, clock: clock)

        let collector = Collector<TrackUpdate>()
        let cancellable = interactor.trackChange.sink { collector.append($0) }
        defer { cancellable.cancel() }

        playback.subject.send(nowPlaying(title: "Track A", artist: "Artist A"))
        await clock.advance(by: .milliseconds(300))
        _ = await collector.waitFor { $0.lyricsState == .resolved }

        playback.subject.send(nil)
        await clock.advance(by: .seconds(3))

        // A titled client answering again — even a muted-style report whose
        // display is suppressed — proves the source is alive: the armed
        // grace must be cancelled, not left to fire on a live display.
        playback.subject.send(nowPlaying(title: "Track A", artist: ""))
        await clock.advance(by: .seconds(30))

        #expect(
            !collector.contains { $0.lyricsState == .idle },
            "a live client's suppressed report cancels the pending clear")

        // A nil run that starts *after* the suppressed report is a new run:
        // it arms a fresh grace and clears on expiry.
        playback.subject.send(nil)
        await clock.advance(by: .seconds(6))
        _ = try #require(await collector.waitFor { $0.lyricsState == .idle })
    }

    @Test("pause (rate 0) never triggers a clear and still reaches playbackPosition")
    func pausedClientStaysDisplayed() async throws {
        let playback = StubPlaybackUseCase()
        let clock = TestClock<Duration>()
        let interactor = makeInteractor(playback: playback, clock: clock)

        let updates = Collector<TrackUpdate>()
        let updatesCancellable = interactor.trackChange.sink { updates.append($0) }
        defer { updatesCancellable.cancel() }

        let positions = Collector<PlaybackPosition>()
        let positionsCancellable = interactor.playbackPosition.sink { positions.append($0) }
        defer { positionsCancellable.cancel() }

        playback.subject.send(nowPlaying(title: "Track A", artist: "Artist A"))
        await clock.advance(by: .milliseconds(300))
        _ = await updates.waitFor { $0.lyricsState == .resolved }

        playback.subject.send(nowPlaying(title: "Track A", artist: "Artist A", playbackRate: 0))
        _ = try #require(await positions.waitFor { $0.playbackRate == 0 })

        await clock.advance(by: .seconds(30))
        #expect(!updates.contains { $0.lyricsState == .idle }, "a paused client keeps the display")
    }
}
