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
    func isAIMetadataCached(track: Track) async -> Bool { true }
}

private struct StubLyricsUseCase: LyricsUseCase, Sendable {
    func fetchLyrics(track: Track) async -> LyricsResult { LyricsResult() }
    func fetchLyrics(candidates: [Track]) async -> LyricsResult { LyricsResult() }
    func parseLyricsContent(from result: LyricsResult?) -> LyricsContent? { nil }
}

private struct StubConfigUseCase: ConfigUseCase, Sendable {
    var appStyle: AppStyle { .init() }
    func reload() -> ConfigReloadOutcome { .updated(appStyle) }
    func template(format: ConfigFormat) -> String? { nil }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { "" }
    var existingConfigPath: String? { nil }
}

// MARK: - Helpers

private final class PositionCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var emissions: [PlaybackPosition] = []

    var snapshot: [PlaybackPosition] { lock.withLock { emissions } }

    func append(_ pos: PlaybackPosition) {
        lock.withLock { emissions.append(pos) }
    }

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
        $0.metadataUseCase = InstantMetadataUseCase()
        $0.lyricsUseCase = StubLyricsUseCase()
        $0.configUseCase = StubConfigUseCase()
    } operation: {
        TrackInteractorImpl()
    }
}

// MARK: - Tests

@Suite("TrackInteractor playback position stream", .serialized)
struct TrackInteractorPlaybackPositionTests {

    @Test("playbackPosition emits snapshot (rawElapsed / timestamp / playbackRate) verbatim from NowPlaying")
    func emitsSnapshotFields() async throws {
        let playback = StubPlaybackUseCase()
        let interactor = makeInteractor(playback: playback)
        let collector = PositionCollector()
        let cancellable = interactor.playbackPosition.sink { collector.append($0) }
        defer { cancellable.cancel() }

        let ts = Date(timeIntervalSinceReferenceDate: 1_000_000)
        playback.subject.send(
            NowPlaying(
                title: "Song", artist: "Artist", artworkData: nil,
                duration: 200, rawElapsed: 42, playbackRate: 1.5, timestamp: ts))

        await collector.waitForCount(1)
        let first = try #require(collector.snapshot.first)
        #expect(first.rawElapsed == 42)
        #expect(first.timestamp == ts)
        #expect(first.playbackRate == 1.5)
    }

    @Test("playbackPosition propagates nil rawElapsed / timestamp and rate 0 (paused) gracefully")
    func emitsNilSnapshotFields() async throws {
        let playback = StubPlaybackUseCase()
        let interactor = makeInteractor(playback: playback)
        let collector = PositionCollector()
        let cancellable = interactor.playbackPosition.sink { collector.append($0) }
        defer { cancellable.cancel() }

        playback.subject.send(
            NowPlaying(
                title: "Song", artist: "Artist", artworkData: nil,
                duration: nil, rawElapsed: nil, playbackRate: 0, timestamp: nil))

        await collector.waitForCount(1)
        let first = try #require(collector.snapshot.first)
        #expect(first.rawElapsed == nil)
        #expect(first.timestamp == nil)
        #expect(first.playbackRate == 0)
    }

    @Test("playbackPosition emits multiple snapshots when NowPlaying changes")
    func emitsMultipleSnapshots() async throws {
        let playback = StubPlaybackUseCase()
        let interactor = makeInteractor(playback: playback)
        let collector = PositionCollector()
        let cancellable = interactor.playbackPosition.sink { collector.append($0) }
        defer { cancellable.cancel() }

        let t1 = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let t2 = Date(timeIntervalSinceReferenceDate: 1_000_010)

        playback.subject.send(
            NowPlaying(
                title: "Song A", artist: "Artist", artworkData: nil,
                duration: 200, rawElapsed: 10, playbackRate: 1.0, timestamp: t1))
        await collector.waitForCount(1)

        playback.subject.send(
            NowPlaying(
                title: "Song B", artist: "Artist", artworkData: nil,
                duration: 200, rawElapsed: 0, playbackRate: 1.0, timestamp: t2))
        await collector.waitForCount(2)

        let snapshots = collector.snapshot
        try #require(snapshots.count == 2)
        #expect(snapshots[0].rawElapsed == 10)
        #expect(snapshots[0].timestamp == t1)
        #expect(snapshots[1].rawElapsed == 0)
        #expect(snapshots[1].timestamp == t2)
    }

    @Test("playbackPosition suppresses 'volume mute' transition (same title, artist disappears)")
    func volumeMutePatternSuppressed() async throws {
        let playback = StubPlaybackUseCase()
        let interactor = makeInteractor(playback: playback)
        let collector = PositionCollector()
        let cancellable = interactor.playbackPosition.sink { collector.append($0) }
        defer { cancellable.cancel() }

        // First: title with non-empty artist -> emits
        playback.subject.send(
            NowPlaying(
                title: "Song", artist: "Artist", artworkData: nil,
                duration: nil, rawElapsed: 1, playbackRate: 1, timestamp: nil))
        await collector.waitForCount(1)

        // Second: same title, artist degrades to empty (system mute / lookup hiccup).
        // activeNowPlaying.compactMap returns nil for this pattern (line 30) — suppressed.
        playback.subject.send(
            NowPlaying(
                title: "Song", artist: "", artworkData: nil,
                duration: nil, rawElapsed: 2, playbackRate: 1, timestamp: nil))

        // Third: artist returns -> emits again. Awaiting count==2 here proves
        // the second send did NOT emit (otherwise count would already be >=2).
        playback.subject.send(
            NowPlaying(
                title: "Song", artist: "Artist", artworkData: nil,
                duration: nil, rawElapsed: 3, playbackRate: 1, timestamp: nil))
        await collector.waitForCount(2)

        let snapshots = collector.snapshot
        try #require(snapshots.count == 2, "second (volume-mute) emission should be filtered out by activeNowPlaying")
        #expect(snapshots[0].rawElapsed == 1)
        #expect(snapshots[1].rawElapsed == 3)
    }
}
