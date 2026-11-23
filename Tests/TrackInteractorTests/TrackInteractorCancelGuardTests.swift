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

/// Metadata stub that parks inside the awaited call the first time it is
/// invoked, so the test can cancel the resolve task while it is provably
/// suspended there — exercising the `Task.isCancelled` guard that follows
/// each await. The flag is consumed, so the replacement track's resolve runs
/// to completion.
private final class ParkingMetadataUseCase: MetadataUseCase, @unchecked Sendable {
    let cacheCheckCalls = Collector<Void>()
    let candidatesCalls = Collector<Void>()
    var parkCacheCheck = true
    var parkCandidates = true

    func resolve(track: Track) async -> Track? { nil }

    func resolveCandidates(track: Track) async -> [Track] {
        candidatesCalls.append(())
        if parkCandidates {
            parkCandidates = false
            _ = await suspendUntilCancelled()
        }
        return []
    }

    func isAIMetadataCached(track: Track) async -> Bool {
        cacheCheckCalls.append(())
        if parkCacheCheck {
            parkCacheCheck = false
            _ = await suspendUntilCancelled()
        }
        return false
    }
}

private final class ParkingLyricsUseCase: LyricsUseCase, @unchecked Sendable {
    let fetchCalls = Collector<Void>()
    var parkFetch = true

    func fetchLyrics(track: Track) async -> LyricsResult { LyricsResult() }

    func fetchLyrics(candidates: [Track]) async -> LyricsResult {
        fetchCalls.append(())
        if parkFetch {
            parkFetch = false
            _ = await suspendUntilCancelled()
        }
        return LyricsResult()
    }

    func parseLyricsContent(from result: LyricsResult?) -> LyricsContent? { nil }
}

private struct StubConfigUseCase: ConfigUseCase, Sendable {
    let style: AppStyle
    var appStyle: AppStyle { style }
    func reload() -> ConfigReloadOutcome { .updated(appStyle) }
    func template(format: ConfigFormat) -> String? { nil }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { "" }
    var existingConfigPath: String? { nil }
}

// MARK: - Helpers

private let aiEndpoint = AIEndpoint(endpoint: "https://api.example.com", model: "gpt-4", apiKey: "sk-test")

private func makeInteractor(
    playback: StubPlaybackUseCase,
    metadata: any MetadataUseCase,
    lyrics: any LyricsUseCase,
    aiConfigured: Bool = false
) -> TrackInteractorImpl {
    withDependencies {
        // ImmediateClock collapses the 300ms debounce; the tests park inside
        // the stubbed awaits, so timing is irrelevant.
        $0.continuousClock = ImmediateClock()
        $0.playbackUseCase = playback
        $0.metadataUseCase = metadata
        $0.lyricsUseCase = lyrics
        $0.configUseCase = StubConfigUseCase(style: AppStyle(ai: aiConfigured ? aiEndpoint : nil))
    } operation: {
        TrackInteractorImpl()
    }
}

private func send(_ playback: StubPlaybackUseCase, title: String) {
    playback.subject.send(
        NowPlaying(
            title: title, artist: "Artist", artworkData: nil,
            duration: nil, rawElapsed: nil, playbackRate: 1, timestamp: nil))
}

// MARK: - Tests

/// Each `await` in `resolveTrack` is followed by a `Task.isCancelled` guard
/// that finishes the inner stream quietly instead of emitting a stale update.
/// Cancelling mid-await is what `switchToLatest` does when the next track
/// arrives — so every test sends track A, proves the resolve is parked inside
/// the target await, then sends track B and asserts the pipeline still
/// delivers B's final update.
@Suite("TrackInteractor resolve cancellation guards", .serialized, .timeLimit(.minutes(1)))
struct TrackInteractorCancelGuardTests {

    @Test("cancel inside the AI-cache check finishes the stale resolve")
    func cancelInsideCacheCheck() async throws {
        let playback = StubPlaybackUseCase()
        let metadata = ParkingMetadataUseCase()
        // Track B's resolve re-enters the same stubs — only the cache check
        // may park, or B would stall behind a cancellation that never comes.
        metadata.parkCandidates = false
        let lyrics = ParkingLyricsUseCase()
        lyrics.parkFetch = false
        let interactor = makeInteractor(
            playback: playback, metadata: metadata, lyrics: lyrics, aiConfigured: true)

        let collector = Collector<TrackUpdate>()
        let cancellable = interactor.trackChange.sink { collector.append($0) }
        defer { cancellable.cancel() }

        send(playback, title: "Track A")
        await metadata.cacheCheckCalls.waitForCount(1)

        send(playback, title: "Track B")
        let final = try #require(
            await collector.waitFor {
                $0.title == "Track B" && ($0.lyricsState == .resolved || $0.lyricsState == .notFound)
            })
        #expect(final.lyricsState != .loading)

        // The cancelled A resolve must never have emitted beyond .loading.
        #expect(
            !collector.contains { $0.title == "Track A" && $0.lyricsState != .loading },
            "a resolve cancelled inside the cache check must not emit a stale update")
    }

    @Test("cancel inside candidate resolution finishes the stale resolve")
    func cancelInsideResolveCandidates() async throws {
        let playback = StubPlaybackUseCase()
        let metadata = ParkingMetadataUseCase()
        metadata.parkCacheCheck = false
        let lyrics = ParkingLyricsUseCase()
        lyrics.parkFetch = false
        let interactor = makeInteractor(
            playback: playback, metadata: metadata, lyrics: lyrics)

        let collector = Collector<TrackUpdate>()
        let cancellable = interactor.trackChange.sink { collector.append($0) }
        defer { cancellable.cancel() }

        send(playback, title: "Track A")
        await metadata.candidatesCalls.waitForCount(1)

        send(playback, title: "Track B")
        let final = try #require(
            await collector.waitFor {
                $0.title == "Track B" && ($0.lyricsState == .resolved || $0.lyricsState == .notFound)
            })
        #expect(final.lyricsState != .loading)

        #expect(
            !collector.contains { $0.title == "Track A" && $0.lyricsState != .loading },
            "a resolve cancelled inside resolveCandidates must not emit a stale update")
    }

    @Test("cancel inside the lyrics fetch finishes the stale resolve")
    func cancelInsideFetchLyrics() async throws {
        let playback = StubPlaybackUseCase()
        let metadata = ParkingMetadataUseCase()
        metadata.parkCacheCheck = false
        metadata.parkCandidates = false
        let lyrics = ParkingLyricsUseCase()
        let interactor = makeInteractor(
            playback: playback, metadata: metadata, lyrics: lyrics)

        let collector = Collector<TrackUpdate>()
        let cancellable = interactor.trackChange.sink { collector.append($0) }
        defer { cancellable.cancel() }

        send(playback, title: "Track A")
        await lyrics.fetchCalls.waitForCount(1)

        send(playback, title: "Track B")
        let final = try #require(
            await collector.waitFor {
                $0.title == "Track B" && ($0.lyricsState == .resolved || $0.lyricsState == .notFound)
            })
        #expect(final.lyricsState != .loading)

        #expect(
            !collector.contains { $0.title == "Track A" && $0.lyricsState != .loading },
            "a resolve cancelled inside fetchLyrics must not emit a stale update")
    }
}
