import Dependencies
import Domain
import Foundation
import LyricsUseCase
import Testing
import os

@testable import TrackHandler

@Suite("TrackHandlerImpl")
struct TrackHandlerImplTests {
    // MARK: - No Track Playing

    @Suite("no track playing")
    struct NoTrack {
        @Test("returns empty info when fetchNowPlaying returns nil")
        func nilNowPlaying() async {
            let info = await fetchWith(nowPlaying: nil)
            #expect(info.title == nil)
            #expect(info.artist == nil)
        }

        @Test("returns empty info when title is nil")
        func nilTitle() async {
            let info = await fetchWith(nowPlaying: .stub(title: nil, artist: "Artist"))
            #expect(info.title == nil)
        }

        @Test("returns empty info when artist is nil")
        func nilArtist() async {
            let info = await fetchWith(nowPlaying: .stub(title: "Song", artist: nil))
            #expect(info.title == nil)
        }
    }

    // MARK: - Default Query (no flags)

    @Suite("default query — no resolve, no lyrics")
    struct DefaultQuery {
        @Test("returns raw title and artist")
        func rawData() async {
            let info = await fetchWith(
                nowPlaying: .stub(title: "Raw Title", artist: "Raw Artist")
            )
            #expect(info.title == "Raw Title")
            #expect(info.artist == "Raw Artist")
        }

        @Test("includes duration and elapsed")
        func durationAndElapsed() async {
            let info = await fetchWith(
                nowPlaying: .stub(title: "Song", artist: "Artist", duration: 240, elapsed: 60)
            )
            #expect(info.duration == 240)
            #expect(info.elapsedTime != nil)
        }

        @Test("does not call metadataUseCase")
        func noMetadata() async {
            let called = CallTracker()
            let info = await fetchWith(
                nowPlaying: .stub(title: "Song", artist: "Artist"),
                metadataHandler: { _ in
                    called.call()
                    return []
                }
            )
            #expect(info.title == "Song")
            #expect(!called.wasCalled)
        }
    }

    // MARK: - Resolve Flag

    @Suite("resolve flag")
    struct ResolveFlag {
        @Test("uses resolved metadata when candidates found")
        func resolved() async {
            let info = await fetchWith(
                nowPlaying: .stub(title: "Raw", artist: "Raw"),
                query: TrackQuery(resolve: true),
                metadataHandler: { _ in [Track(title: "Resolved", artist: "Resolved Artist", duration: nil)] }
            )
            #expect(info.title == "Resolved")
            #expect(info.artist == "Resolved Artist")
        }

        @Test("falls back to raw when no candidates")
        func noCandidates() async {
            let info = await fetchWith(
                nowPlaying: .stub(title: "Raw", artist: "Raw"),
                query: TrackQuery(resolve: true),
                metadataHandler: { _ in [] }
            )
            #expect(info.title == "Raw")
            #expect(info.artist == "Raw")
        }
    }

    // MARK: - Lyrics Flag

    @Suite("lyrics flag")
    struct LyricsFlag {
        @Test("lyrics flag implies resolve")
        func impliesResolve() async {
            let called = CallTracker()
            _ = await fetchWith(
                nowPlaying: .stub(title: "Song", artist: "Artist"),
                query: TrackQuery(lyrics: true),
                metadataHandler: { _ in
                    called.call()
                    return []
                }
            )
            #expect(called.wasCalled)
        }

        @Test("includes plain lyrics from result")
        func plainLyrics() async {
            let info = await fetchWith(
                nowPlaying: .stub(title: "Song", artist: "Artist"),
                query: TrackQuery(lyrics: true),
                lyricsHandler: { _ in LyricsResult(plainLyrics: "La la la") }
            )
            #expect(info.lyrics == "La la la")
        }

        @Test("uses trackName from lyrics result over raw title")
        func lyricsTrackName() async {
            let info = await fetchWith(
                nowPlaying: .stub(title: "Raw", artist: "Raw"),
                query: TrackQuery(lyrics: true),
                lyricsHandler: { _ in LyricsResult(trackName: "Lyrics Title", artistName: "Lyrics Artist") }
            )
            #expect(info.title == "Lyrics Title")
            #expect(info.artist == "Lyrics Artist")
        }
    }
}

// MARK: - Helpers

private final class CallTracker: Sendable {
    private let _called = OSAllocatedUnfairLock(initialState: false)
    var wasCalled: Bool { _called.withLock { $0 } }
    func call() { _called.withLock { $0 = true } }
}

private func fetchWith(
    nowPlaying: NowPlaying?,
    query: TrackQuery = TrackQuery(),
    metadataHandler: @escaping @Sendable (Track) async -> [Track] = { _ in [] },
    lyricsHandler: @escaping @Sendable ([Track]) async -> LyricsResult = { _ in LyricsResult() }
) async -> NowPlayingInfo {
    await withDependencies {
        $0.playbackUseCase = StubPlaybackUseCase(nowPlaying: nowPlaying)
        $0.metadataUseCase = StubMetadataUseCase(handler: metadataHandler)
        $0.lyricsUseCase = StubLyricsUseCase(handler: lyricsHandler)
    } operation: {
        await TrackHandlerImpl().fetchInfo(query: query)
    }
}

private struct StubPlaybackUseCase: PlaybackUseCase {
    let nowPlaying: NowPlaying?
    func fetchNowPlaying() async -> NowPlaying? { nowPlaying }
    func observeNowPlaying() -> AsyncStream<NowPlaying?> { AsyncStream { $0.finish() } }
    func elapsedTime(for np: NowPlaying) -> TimeInterval? { np.rawElapsed }
}

private struct StubMetadataUseCase: MetadataUseCase {
    let handler: @Sendable (Track) async -> [Track]
    func resolve(track: Track) async -> Track? { await handler(track).first }
    func resolveCandidates(track: Track) async -> [Track] { await handler(track) }
}

private struct StubLyricsUseCase: LyricsUseCase {
    let handler: @Sendable ([Track]) async -> LyricsResult
    func fetchLyrics(track: Track) async -> LyricsResult { await handler([track]) }
    func fetchLyrics(candidates: [Track]) async -> LyricsResult { await handler(candidates) }
    func parseLyricsContent(from result: LyricsResult?) -> LyricsContent? {
        LyricsUseCaseImpl().parseLyricsContent(from: result)
    }
}

extension NowPlaying {
    fileprivate static func stub(
        title: String? = nil,
        artist: String? = nil,
        duration: TimeInterval? = nil,
        elapsed: TimeInterval? = nil
    ) -> NowPlaying {
        NowPlaying(
            title: title, artist: artist, artworkData: nil,
            duration: duration, rawElapsed: elapsed,
            playbackRate: 1.0, timestamp: nil
        )
    }
}
