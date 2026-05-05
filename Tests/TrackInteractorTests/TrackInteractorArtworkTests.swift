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

private final class ArtworkCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var emissions: [Data?] = []

    var snapshot: [Data?] { lock.withLock { emissions } }

    func append(_ data: Data?) {
        lock.withLock { emissions.append(data) }
    }

    func waitForCount(_ target: Int, timeout: Duration = .seconds(2)) async {
        let deadline = ContinuousClock.now + timeout
        while snapshot.count < target, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Polls until `timeout` and returns `true` if the emission count stayed at `expected`.
    /// Use for negative assertions ("no new emission arrived"). Fails fast on extra emission.
    func isStableAt(_ expected: Int, timeout: Duration = .milliseconds(200)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
            if snapshot.count != expected { return false }
        }
        return snapshot.count == expected
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

private func nowPlaying(title: String?, artist: String?, artwork: Data?) -> NowPlaying {
    NowPlaying(
        title: title, artist: artist, artworkData: artwork,
        duration: nil, rawElapsed: nil, playbackRate: 1, timestamp: nil
    )
}

// MARK: - Tests

@Suite("TrackInteractor artwork stream", .serialized)
struct TrackInteractorArtworkTests {

    @Test("artwork stays stable when only artworkData changes (volume mute scenario)")
    func artworkStableOnVolumeMute() async {
        let playback = StubPlaybackUseCase()
        let interactor = makeInteractor(playback: playback)
        let collector = ArtworkCollector()
        let cancellable = interactor.artwork.sink { collector.append($0) }
        defer { cancellable.cancel() }

        let trackArt = Data([0xFF, 0xD8, 0xFF])
        let chromeIcon = Data([0x89, 0x50, 0x4E, 0x47])

        playback.subject.send(nowPlaying(title: "Song", artist: "Artist", artwork: trackArt))
        await collector.waitForCount(1)
        #expect(collector.snapshot == [trackArt])

        playback.subject.send(nowPlaying(title: "Song", artist: "Artist", artwork: chromeIcon))
        let stableAfterChrome = await collector.isStableAt(1)
        #expect(stableAfterChrome, "Chrome icon at volume 0 must not propagate to artwork stream")
        #expect(collector.snapshot == [trackArt])

        playback.subject.send(nowPlaying(title: "Song", artist: "Artist", artwork: trackArt))
        let stableAfterRestore = await collector.isStableAt(1)
        #expect(stableAfterRestore, "Restoring artwork on the same track must not re-emit")
        #expect(collector.snapshot == [trackArt])
    }

    @Test("artwork emits anew when title changes")
    func artworkEmitsOnTitleChange() async {
        let playback = StubPlaybackUseCase()
        let interactor = makeInteractor(playback: playback)
        let collector = ArtworkCollector()
        let cancellable = interactor.artwork.sink { collector.append($0) }
        defer { cancellable.cancel() }

        let artA = Data([0x01])
        let artB = Data([0x02])

        playback.subject.send(nowPlaying(title: "Song A", artist: "Artist", artwork: artA))
        await collector.waitForCount(1)

        playback.subject.send(nowPlaying(title: "Song B", artist: "Artist", artwork: artB))
        await collector.waitForCount(2)

        #expect(collector.snapshot == [artA, artB])
    }

    @Test("artwork emits anew when artist changes")
    func artworkEmitsOnArtistChange() async {
        let playback = StubPlaybackUseCase()
        let interactor = makeInteractor(playback: playback)
        let collector = ArtworkCollector()
        let cancellable = interactor.artwork.sink { collector.append($0) }
        defer { cancellable.cancel() }

        let artA = Data([0x01])
        let artB = Data([0x02])

        playback.subject.send(nowPlaying(title: "Song", artist: "Artist A", artwork: artA))
        await collector.waitForCount(1)

        playback.subject.send(nowPlaying(title: "Song", artist: "Artist B", artwork: artB))
        await collector.waitForCount(2)

        #expect(collector.snapshot == [artA, artB])
    }

    @Test("sameTrack treats nil and empty-string artist as the same value")
    func sameTrackNormalizesEmptyArtist() {
        let withArtist = nowPlaying(title: "Song", artist: "Artist", artwork: nil)
        let nilArtist = nowPlaying(title: "Song", artist: nil, artwork: nil)
        let emptyArtist = nowPlaying(title: "Song", artist: "", artwork: nil)
        let differentTitle = nowPlaying(title: "Other", artist: "Artist", artwork: nil)

        #expect(TrackInteractorImpl.sameTrack(nilArtist, emptyArtist), "nil and empty should match (both treated as missing artist)")
        #expect(TrackInteractorImpl.sameTrack(withArtist, nilArtist), "non-empty and nil should match when title is identical (artist degradation)")
        #expect(!TrackInteractorImpl.sameTrack(withArtist, differentTitle), "different title must not match")
    }
}
