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

/// Metadata stub whose `isAIMetadataCached` answer is configurable so the
/// processing-indicator branch in `resolveTrack` can be exercised both ways.
private struct ConfigurableMetadataUseCase: MetadataUseCase, Sendable {
    let aiCached: Bool
    let candidates: [Track]
    func resolve(track: Track) async -> Track? { candidates.first }
    func resolveCandidates(track: Track) async -> [Track] { candidates }
    func isAIMetadataCached(track: Track) async -> Bool { aiCached }
}

private struct StubLyricsUseCase: LyricsUseCase, Sendable {
    func fetchLyrics(track: Track) async -> LyricsResult { LyricsResult() }
    func fetchLyrics(candidates: [Track]) async -> LyricsResult { LyricsResult() }
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
    aiConfigured: Bool,
    aiCached: Bool
) -> TrackInteractorImpl {
    withDependencies {
        // ImmediateClock collapses the 300ms debounce so the whole resolveTrack
        // pipeline runs to completion without manual clock advancement — these
        // tests assert on which updates are emitted, not on their timing.
        $0.continuousClock = ImmediateClock()
        $0.playbackUseCase = playback
        $0.metadataUseCase = ConfigurableMetadataUseCase(aiCached: aiCached, candidates: [])
        $0.lyricsUseCase = StubLyricsUseCase()
        $0.configUseCase = StubConfigUseCase(style: AppStyle(ai: aiConfigured ? aiEndpoint : nil))
    } operation: {
        TrackInteractorImpl()
    }
}

private func sendTrack(_ playback: StubPlaybackUseCase) {
    playback.subject.send(
        NowPlaying(
            title: "Song", artist: "Artist", artworkData: nil,
            duration: nil, rawElapsed: nil, playbackRate: 1, timestamp: nil))
}

// MARK: - Tests

@Suite("TrackInteractor AI processing indicator", .serialized, .timeLimit(.minutes(1)))
struct TrackInteractorAIProcessingTests {

    @Test("emits aiResolving update when AI is configured and the LLM cache misses")
    func emitsWhenConfiguredAndMissed() async throws {
        let playback = StubPlaybackUseCase()
        let interactor = makeInteractor(playback: playback, aiConfigured: true, aiCached: false)

        let collector = Collector<TrackUpdate>()
        let cancellable = interactor.trackChange.sink { collector.append($0) }
        defer { cancellable.cancel() }

        sendTrack(playback)
        await collector.waitFor { $0.aiResolving }

        #expect(
            collector.contains { $0.aiResolving && $0.title == "Song" && $0.artist == "Artist" },
            "an aiResolving update should be emitted on cache miss with AI configured")
    }

    @Test("does not emit aiResolving update when the LLM cache hits")
    func noEmitWhenCached() async throws {
        let playback = StubPlaybackUseCase()
        let interactor = makeInteractor(playback: playback, aiConfigured: true, aiCached: true)

        let collector = Collector<TrackUpdate>()
        let cancellable = interactor.trackChange.sink { collector.append($0) }
        defer { cancellable.cancel() }

        sendTrack(playback)
        await collector.waitFor { $0.lyricsState == .notFound || $0.lyricsState == .resolved }

        #expect(!collector.contains(where: \.aiResolving), "cache hit must not show the processing indicator")
    }

    @Test("does not emit aiResolving update when no AI endpoint is configured")
    func noEmitWhenAIAbsent() async throws {
        let playback = StubPlaybackUseCase()
        let interactor = makeInteractor(playback: playback, aiConfigured: false, aiCached: false)

        let collector = Collector<TrackUpdate>()
        let cancellable = interactor.trackChange.sink { collector.append($0) }
        defer { cancellable.cancel() }

        sendTrack(playback)
        await collector.waitFor { $0.lyricsState == .notFound || $0.lyricsState == .resolved }

        #expect(!collector.contains(where: \.aiResolving), "no AI endpoint means no processing indicator")
    }
}
