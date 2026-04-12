@preconcurrency import Combine
import Dependencies
import Domain
import Foundation
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
    func template(format: ConfigFormat) -> String? { nil }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { "" }
    var existingConfigPath: String? { nil }
}

// MARK: - Helpers

private final class UpdateCollector: @unchecked Sendable {
    private struct Waiter {
        let id: UUID
        let predicate: @Sendable (TrackUpdate) -> Bool
        let continuation: CheckedContinuation<TrackUpdate, Never>
    }

    private let lock = NSLock()
    private var _updates: [TrackUpdate] = []
    private var waiters: [Waiter] = []

    var updates: [TrackUpdate] {
        lock.withLock { _updates }
    }

    var count: Int {
        lock.withLock { _updates.count }
    }

    func append(_ update: TrackUpdate) {
        let matchedContinuations = lock.withLock { () -> [CheckedContinuation<TrackUpdate, Never>] in
            _updates.append(update)
            let matched = waiters.filter { $0.predicate(update) }
            waiters.removeAll { waiter in
                matched.contains { $0.id == waiter.id }
            }
            return matched.map(\.continuation)
        }

        for continuation in matchedContinuations {
            continuation.resume(returning: update)
        }
    }

    func contains(where predicate: (TrackUpdate) -> Bool) -> Bool {
        lock.withLock { _updates.contains(where: predicate) }
    }

    func waitFor(predicate: @escaping @Sendable (TrackUpdate) -> Bool) async -> TrackUpdate {
        if let existing = lock.withLock({ _updates.first(where: predicate) }) {
            return existing
        }
        let waiterID = UUID()
        return await withCheckedContinuation { continuation in
            let existing = lock.withLock { () -> TrackUpdate? in
                if let existing = _updates.first(where: predicate) {
                    return existing
                }
                waiters.append(Waiter(id: waiterID, predicate: predicate, continuation: continuation))
                return nil
            }

            if let existing {
                continuation.resume(returning: existing)
            }
        }
    }
}

private func makeInteractor(
    playback: StubPlaybackUseCase,
    metadata: any MetadataUseCase = InstantMetadataUseCase(),
    lyrics: any LyricsUseCase = StubLyricsUseCase(),
    config: any ConfigUseCase = StubConfigUseCase(),
    clock: any Clock<Duration> = ImmediateClock()
) -> TrackInteractorImpl {
    withDependencies {
        $0.continuousClock = clock
        $0.playbackUseCase = playback
        $0.metadataUseCase = metadata
        $0.lyricsUseCase = lyrics
        $0.configUseCase = config
    } operation: {
        TrackInteractorImpl()
    }
}

// MARK: - Tests

@Suite("TrackInteractor race condition", .serialized)
struct TrackInteractorRaceTests {

    @Test("rapid track change cancels stale resolution — only latest track emits resolved")
    func rapidTrackChangeCancelsStale() async throws {
        let playback = StubPlaybackUseCase()
        let clock = TestClock<Duration>()
        let interactor = makeInteractor(playback: playback, clock: clock)

        let collector = UpdateCollector()
        let cancellable = interactor.trackChange
            .sink { collector.append($0) }
        defer { cancellable.cancel() }

        playback.subject.send(
            NowPlaying(title: "Track A", artist: "Artist A", artworkData: nil, duration: nil, rawElapsed: nil, playbackRate: 1, timestamp: nil))

        _ = await collector.waitFor { update in
            update.title == "Track A" && update.lyricsState == .loading
        }

        playback.subject.send(
            NowPlaying(title: "Track B", artist: "Artist B", artworkData: nil, duration: nil, rawElapsed: nil, playbackRate: 1, timestamp: nil))

        await clock.advance(by: .milliseconds(300))
        _ = await collector.waitFor { update in
            update.title == "Track B" && (update.lyricsState == .resolved || update.lyricsState == .notFound)
        }

        let resolved = collector.updates.filter { $0.lyricsState == .resolved || $0.lyricsState == .notFound }
        #expect(!resolved.contains { $0.title == "Track A" }, "Track A resolution should be cancelled")
        #expect(resolved.contains { $0.title == "Track B" }, "Track B resolution should complete")
    }

    @Test("nil NowPlaying does not emit TrackUpdate — last track info is retained")
    func nilNowPlayingKeepsLastTrack() async throws {
        let playback = StubPlaybackUseCase()
        let clock = TestClock<Duration>()
        let interactor = makeInteractor(playback: playback, clock: clock)

        let collector = UpdateCollector()
        let cancellable = interactor.trackChange
            .sink { collector.append($0) }
        defer { cancellable.cancel() }

        playback.subject.send(
            NowPlaying(
                title: "Track A", artist: "Artist A", artworkData: nil,
                duration: nil, rawElapsed: nil, playbackRate: 1, timestamp: nil))

        await clock.advance(by: .milliseconds(300))
        _ = await collector.waitFor { update in
            update.title == "Track A" && (update.lyricsState == .resolved || update.lyricsState == .notFound)
        }

        #expect(!collector.updates.isEmpty, "Track A should have emitted before nil")

        let countBeforeNil = collector.count

        playback.subject.send(nil)

        await Task.yield()
        await MainActor.run {}

        let afterNil = collector.updates.dropFirst(countBeforeNil)
        #expect(afterNil.isEmpty, "nil NowPlaying should not emit any TrackUpdate — last track stays visible")
    }

    @Test("track A loading emits but resolved does not when B arrives quickly")
    func staleLoadingVisibleButResolvedCancelled() async throws {
        let playback = StubPlaybackUseCase()
        let clock = TestClock<Duration>()
        let interactor = makeInteractor(playback: playback, clock: clock)

        let collector = UpdateCollector()
        let cancellable = interactor.trackChange
            .sink { collector.append($0) }
        defer { cancellable.cancel() }

        playback.subject.send(
            NowPlaying(title: "Track A", artist: "Artist A", artworkData: nil, duration: nil, rawElapsed: nil, playbackRate: 1, timestamp: nil))

        _ = await collector.waitFor { update in
            update.title == "Track A" && update.lyricsState == .loading
        }

        playback.subject.send(
            NowPlaying(title: "Track B", artist: "Artist B", artworkData: nil, duration: nil, rawElapsed: nil, playbackRate: 1, timestamp: nil))

        await clock.advance(by: .milliseconds(300))
        _ = await collector.waitFor { update in
            update.title == "Track B" && (update.lyricsState == .resolved || update.lyricsState == .notFound)
        }

        let resolvedA = collector.updates.filter { $0.title == "Track A" && ($0.lyricsState == .resolved || $0.lyricsState == .notFound) }
        #expect(resolvedA.isEmpty, "Track A resolution must be cancelled by switchToLatest")
        #expect(
            collector.contains { $0.title == "Track B" && ($0.lyricsState == .resolved || $0.lyricsState == .notFound) },
            "Track B should still resolve"
        )
    }

    // MARK: - Volume mute deduplication

    @Test("dedup logic: same title with empty artist on either side is treated as same track")
    func dedupLogicVolumeMute() {
        let isDuplicate: (NowPlaying, NowPlaying) -> Bool = { prev, cur in
            let prevArtist = prev.artist ?? ""
            let curArtist = cur.artist ?? ""
            guard !prevArtist.isEmpty, !curArtist.isEmpty else {
                return prev.title == cur.title
            }
            return prev.title == cur.title && prevArtist == curArtist
        }

        let normal = NowPlaying(
            title: "Song", artist: "Artist", artworkData: nil,
            duration: nil, rawElapsed: nil, playbackRate: 1, timestamp: nil)
        let muted = NowPlaying(
            title: "Song", artist: "", artworkData: nil,
            duration: nil, rawElapsed: nil, playbackRate: 1, timestamp: nil)
        let nilArtist = NowPlaying(
            title: "Song", artist: nil, artworkData: nil,
            duration: nil, rawElapsed: nil, playbackRate: 1, timestamp: nil)
        let differentTrack = NowPlaying(
            title: "Other Song", artist: "Artist", artworkData: nil,
            duration: nil, rawElapsed: nil, playbackRate: 1, timestamp: nil)
        let sameTitleDiffArtist = NowPlaying(
            title: "Song", artist: "Other Artist", artworkData: nil,
            duration: nil, rawElapsed: nil, playbackRate: 1, timestamp: nil)

        #expect(isDuplicate(normal, muted), "Muted (empty artist) should match normal")
        #expect(isDuplicate(muted, normal), "Restored should match muted")
        #expect(isDuplicate(normal, nilArtist), "Nil artist should match normal")
        #expect(!isDuplicate(normal, differentTrack), "Different title should not match")
        #expect(!isDuplicate(normal, sameTitleDiffArtist), "Different non-empty artist should not match")
        #expect(isDuplicate(muted, muted), "Both empty artist, same title should match")
    }
}
