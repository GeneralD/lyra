@preconcurrency import Combine
import Dependencies
import Domain
import Foundation
import Testing

@testable import TrackInteractor

// MARK: - Stubs

private final class StubPlaybackUseCase: PlaybackUseCase, @unchecked Sendable {
    let subject = PassthroughSubject<NowPlaying?, Never>()

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

private struct DelayedMetadataUseCase: MetadataUseCase, Sendable {
    let delay: Duration

    func resolve(track: Track) async -> Track? { nil }
    func resolveCandidates(track: Track) async -> [Track] {
        try? await Task.sleep(for: delay)
        return [track]
    }
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
    private let lock = NSLock()
    private var _updates: [TrackUpdate] = []

    var updates: [TrackUpdate] {
        lock.withLock { _updates }
    }

    var count: Int {
        lock.withLock { _updates.count }
    }

    func append(_ update: TrackUpdate) {
        lock.withLock { _updates.append(update) }
    }

    func contains(where predicate: (TrackUpdate) -> Bool) -> Bool {
        lock.withLock { _updates.contains(where: predicate) }
    }
}

private struct WaitUntilTimeout: Error, CustomStringConvertible {
    let timeout: Duration
    let label: String
    var description: String { "Timed out after \(timeout) waiting for \(label)" }
}

private func waitUntil(
    timeout: Duration = .seconds(5),
    _ label: String = "condition",
    condition: @Sendable () -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else {
            throw WaitUntilTimeout(timeout: timeout, label: label)
        }
        await MainActor.run {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
    }
}

private func makeInteractor(
    playback: StubPlaybackUseCase,
    metadata: any MetadataUseCase = InstantMetadataUseCase(),
    lyrics: any LyricsUseCase = StubLyricsUseCase(),
    config: any ConfigUseCase = StubConfigUseCase()
) -> TrackInteractorImpl {
    withDependencies {
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
        let interactor = makeInteractor(
            playback: playback,
            metadata: DelayedMetadataUseCase(delay: .milliseconds(500))
        )

        let collector = UpdateCollector()
        let cancellable = interactor.trackChange
            .sink { collector.append($0) }
        defer { cancellable.cancel() }

        await MainActor.run { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1)) }

        playback.subject.send(
            NowPlaying(title: "Track A", artist: "Artist A", artworkData: nil, duration: nil, rawElapsed: nil, playbackRate: 1, timestamp: nil))

        try await waitUntil("Track A loading") {
            collector.contains { $0.title == "Track A" && $0.lyricsState == .loading }
        }

        playback.subject.send(
            NowPlaying(title: "Track B", artist: "Artist B", artworkData: nil, duration: nil, rawElapsed: nil, playbackRate: 1, timestamp: nil))

        try await waitUntil("Track B resolved") {
            collector.contains { $0.title == "Track B" && ($0.lyricsState == .resolved || $0.lyricsState == .notFound) }
        }

        let resolved = collector.updates.filter { $0.lyricsState == .resolved || $0.lyricsState == .notFound }
        #expect(!resolved.contains { $0.title == "Track A" }, "Track A resolution should be cancelled")
        #expect(resolved.contains { $0.title == "Track B" }, "Track B resolution should complete")
    }

    @Test("nil NowPlaying does not emit TrackUpdate — last track info is retained")
    func nilNowPlayingKeepsLastTrack() async throws {
        let playback = StubPlaybackUseCase()
        let interactor = makeInteractor(playback: playback)

        let collector = UpdateCollector()
        let cancellable = interactor.trackChange
            .sink { collector.append($0) }
        defer { cancellable.cancel() }

        await MainActor.run { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1)) }

        playback.subject.send(
            NowPlaying(
                title: "Track A", artist: "Artist A", artworkData: nil,
                duration: nil, rawElapsed: nil, playbackRate: 1, timestamp: nil))

        try await waitUntil("Track A resolved") {
            collector.contains { $0.title == "Track A" && ($0.lyricsState == .resolved || $0.lyricsState == .notFound) }
        }

        #expect(!collector.updates.isEmpty, "Track A should have emitted before nil")

        let countBeforeNil = collector.count

        playback.subject.send(nil)

        await MainActor.run { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1)) }

        let afterNil = collector.updates.dropFirst(countBeforeNil)
        #expect(afterNil.isEmpty, "nil NowPlaying should not emit any TrackUpdate — last track stays visible")
    }

    @Test("track A loading emits but resolved does not when B arrives quickly")
    func staleLoadingVisibleButResolvedCancelled() async throws {
        let playback = StubPlaybackUseCase()
        let interactor = makeInteractor(
            playback: playback,
            metadata: DelayedMetadataUseCase(delay: .milliseconds(500))
        )

        let collector = UpdateCollector()
        let cancellable = interactor.trackChange
            .sink { collector.append($0) }
        defer { cancellable.cancel() }

        await MainActor.run { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1)) }

        playback.subject.send(
            NowPlaying(title: "Track A", artist: "Artist A", artworkData: nil, duration: nil, rawElapsed: nil, playbackRate: 1, timestamp: nil))

        try await waitUntil("Track A loading") {
            collector.contains { $0.title == "Track A" && $0.lyricsState == .loading }
        }

        playback.subject.send(
            NowPlaying(title: "Track B", artist: "Artist B", artworkData: nil, duration: nil, rawElapsed: nil, playbackRate: 1, timestamp: nil))

        try await waitUntil("Track B resolved") {
            collector.contains { $0.title == "Track B" && ($0.lyricsState == .resolved || $0.lyricsState == .notFound) }
        }

        let resolvedA = collector.updates.filter { $0.title == "Track A" && ($0.lyricsState == .resolved || $0.lyricsState == .notFound) }
        #expect(resolvedA.isEmpty, "Track A resolution must be cancelled by switchToLatest")
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
