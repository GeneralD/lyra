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

private struct GuessingMetadataUseCase: MetadataUseCase, Sendable {
    func resolve(track: Track) async -> Track? { Track(title: "Wrong Guess", artist: "Wrong Artist") }
    func resolveCandidates(track: Track) async -> [Track] { [Track(title: "Wrong Guess", artist: "Wrong Artist")] }
    func isAIMetadataCached(track: Track) async -> Bool { true }
}

private struct NotFoundLyricsUseCase: LyricsUseCase, Sendable {
    func fetchLyrics(track: Track) async -> LyricsResult { LyricsResult() }
    func fetchLyrics(candidates: [Track]) async -> LyricsResult { LyricsResult() }
    func parseLyricsContent(from result: LyricsResult?) -> LyricsContent? { nil }
}

private struct StubConfigUseCase: ConfigUseCase, Sendable {
    var appStyle: AppStyle { .init() }
    func template(format: ConfigFormat) -> String? { nil }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { "" }
    var existingConfigPath: String? { nil }
}

// MARK: - Helpers

private final class TrackUpdateCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var updates: [TrackUpdate] = []

    var snapshot: [TrackUpdate] { lock.withLock { updates } }

    func append(_ update: TrackUpdate) { lock.withLock { updates.append(update) } }

    func waitForCount(_ target: Int, timeout: Duration = .seconds(2)) async {
        let deadline = ContinuousClock.now + timeout
        while snapshot.count < target, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

private func makeInteractor(playback: StubPlaybackUseCase) -> TrackInteractorImpl {
    withDependencies {
        $0.continuousClock = ImmediateClock()
        $0.playbackUseCase = playback
        $0.metadataUseCase = GuessingMetadataUseCase()
        $0.lyricsUseCase = NotFoundLyricsUseCase()
        $0.configUseCase = StubConfigUseCase()
    } operation: {
        TrackInteractorImpl()
    }
}

private func nowPlaying(title: String?, artist: String?) -> NowPlaying {
    NowPlaying(
        title: title, artist: artist, artworkData: nil,
        duration: nil, rawElapsed: nil, playbackRate: 1, timestamp: nil
    )
}

// MARK: - Tests

@Suite("TrackInteractor display fallback", .serialized)
struct TrackInteractorFallbackDisplayTests {
    @Test("falls back to raw title/artist, not the unvalidated candidate guess, when lyrics are not found")
    func fallsBackToRawWhenLyricsNotFound() async {
        let playback = StubPlaybackUseCase()
        let interactor = makeInteractor(playback: playback)
        let collector = TrackUpdateCollector()
        let cancellable = interactor.trackChange.sink { collector.append($0) }
        defer { cancellable.cancel() }

        playback.subject.send(nowPlaying(title: "Raw Title", artist: "Raw Artist"))
        await collector.waitForCount(3)

        let final = collector.snapshot.last
        #expect(final?.title == "Raw Title")
        #expect(final?.artist == "Raw Artist")
        #expect(final?.lyricsState == .notFound)
    }
}
