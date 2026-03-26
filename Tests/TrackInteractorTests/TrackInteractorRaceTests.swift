@preconcurrency import Combine
import Dependencies
import Domain
import Foundation
import Testing

@testable import TrackInteractor

// MARK: - Stubs

/// PlaybackUseCase that emits controlled NowPlaying values.
private final class StubPlaybackUseCase: PlaybackUseCase, @unchecked Sendable {
    let subject = PassthroughSubject<NowPlaying?, Never>()

    func observeNowPlaying() -> AsyncStream<NowPlaying?> {
        AsyncStream { continuation in
            let cancellable = subject.sink(
                receiveCompletion: { _ in continuation.finish() },
                receiveValue: { continuation.yield($0) }
            )
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }
}

/// MetadataUseCase with configurable delay to simulate slow resolution.
private struct DelayedMetadataUseCase: MetadataUseCase, Sendable {
    let delay: Duration

    func resolve(track: Track) async -> Track? { nil }
    func resolveCandidates(track: Track) async -> [Track] {
        try? await Task.sleep(for: delay)
        return [track]
    }
}

/// Instant MetadataUseCase — no delay.
private struct InstantMetadataUseCase: MetadataUseCase, Sendable {
    func resolve(track: Track) async -> Track? { nil }
    func resolveCandidates(track: Track) async -> [Track] { [] }
}

/// LyricsUseCase that returns identifiable lyrics per track.
private struct StubLyricsUseCase: LyricsUseCase, Sendable {
    func fetchLyrics(track: Track) async -> LyricsResult {
        LyricsResult(trackName: track.title, artistName: track.artist, syncedLyrics: "[\(track.title)]")
    }

    func fetchLyrics(candidates: [Track]) async -> LyricsResult {
        guard let first = candidates.first else { return LyricsResult() }
        return await fetchLyrics(track: first)
    }
}

/// ConfigUseCase stub.
private struct StubConfigUseCase: ConfigUseCase, Sendable {
    var appStyle: AppStyle { .init() }
    func template(format: ConfigFormat) -> String? { nil }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { "" }
}

// MARK: - Tests

@Suite("TrackInteractor race condition")
struct TrackInteractorRaceTests {

    @Test("rapid track change cancels stale resolution — only latest track emits resolved")
    func rapidTrackChangeCancelsStale() async throws {
        let playback = StubPlaybackUseCase()

        let interactor = withDependencies {
            $0.playbackUseCase = playback
            $0.metadataUseCase = DelayedMetadataUseCase(delay: .milliseconds(500))
            $0.lyricsUseCase = StubLyricsUseCase()
            $0.configUseCase = StubConfigUseCase()
        } operation: {
            TrackInteractorImpl()
        }

        var received: [TrackUpdate] = []
        let cancellable = interactor.trackChange
            .sink { received.append($0) }

        // Send track A
        playback.subject.send(
            NowPlaying(title: "Track A", artist: "Artist A", artworkData: nil, duration: nil, rawElapsed: nil, playbackRate: 1, timestamp: nil))

        // Wait just enough for loading to emit but not for resolution to complete
        try await Task.sleep(for: .milliseconds(100))

        // Send track B before A resolves (A's metadata takes 500ms)
        playback.subject.send(
            NowPlaying(title: "Track B", artist: "Artist B", artworkData: nil, duration: nil, rawElapsed: nil, playbackRate: 1, timestamp: nil))

        // Wait for B to fully resolve
        try await Task.sleep(for: .milliseconds(1500))

        cancellable.cancel()

        // Filter to only resolved updates (not loading)
        let resolved = received.filter { $0.lyricsState == .resolved || $0.lyricsState == .notFound }

        // Track A's resolved should NOT be present (cancelled by switchToLatest)
        let hasTrackA = resolved.contains { $0.title == "Track A" }
        let hasTrackB = resolved.contains { $0.title == "Track B" }

        #expect(!hasTrackA, "Track A resolution should be cancelled")
        #expect(hasTrackB, "Track B resolution should complete")
    }

    @Test("nil NowPlaying does not emit TrackUpdate — last track info is retained")
    func nilNowPlayingKeepsLastTrack() async throws {
        let playback = StubPlaybackUseCase()

        let interactor = withDependencies {
            $0.playbackUseCase = playback
            $0.metadataUseCase = InstantMetadataUseCase()
            $0.lyricsUseCase = StubLyricsUseCase()
            $0.configUseCase = StubConfigUseCase()
        } operation: {
            TrackInteractorImpl()
        }

        var received: [TrackUpdate] = []
        let cancellable = interactor.trackChange
            .sink { received.append($0) }

        // Send a track
        playback.subject.send(
            NowPlaying(
                title: "Track A", artist: "Artist A", artworkData: nil,
                duration: nil, rawElapsed: nil, playbackRate: 1, timestamp: nil))

        try await Task.sleep(for: .milliseconds(800))

        // Send nil (playback stopped)
        playback.subject.send(nil)

        try await Task.sleep(for: .milliseconds(300))

        cancellable.cancel()

        // nil NowPlaying must NOT produce any TrackUpdate (no "idle/clear" emission)
        // The UI intentionally keeps showing the last track info
        let afterNil = received.filter { $0.title != "Track A" }
        #expect(afterNil.isEmpty, "nil NowPlaying should not emit any TrackUpdate — last track stays visible")
    }

    @Test("track A loading emits but resolved does not when B arrives quickly")
    func staleLoadingVisibleButResolvedCancelled() async throws {
        let playback = StubPlaybackUseCase()

        let interactor = withDependencies {
            $0.playbackUseCase = playback
            $0.metadataUseCase = DelayedMetadataUseCase(delay: .milliseconds(500))
            $0.lyricsUseCase = StubLyricsUseCase()
            $0.configUseCase = StubConfigUseCase()
        } operation: {
            TrackInteractorImpl()
        }

        var received: [TrackUpdate] = []
        let cancellable = interactor.trackChange
            .sink { received.append($0) }

        playback.subject.send(
            NowPlaying(title: "Track A", artist: "Artist A", artworkData: nil, duration: nil, rawElapsed: nil, playbackRate: 1, timestamp: nil))

        try await Task.sleep(for: .milliseconds(100))

        playback.subject.send(
            NowPlaying(title: "Track B", artist: "Artist B", artworkData: nil, duration: nil, rawElapsed: nil, playbackRate: 1, timestamp: nil))

        try await Task.sleep(for: .milliseconds(1500))

        cancellable.cancel()

        // Loading for Track A may appear (it's emitted immediately)
        let loadingA = received.filter { $0.title == "Track A" && $0.lyricsState == .loading }
        // But resolved for Track A must NOT appear
        let resolvedA = received.filter { $0.title == "Track A" && ($0.lyricsState == .resolved || $0.lyricsState == .notFound) }

        #expect(resolvedA.isEmpty, "Track A resolution must be cancelled by switchToLatest")
        // Loading A is allowed (it emits before cancellation)
    }
}
