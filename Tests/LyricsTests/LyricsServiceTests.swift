import Dependencies
import Foundation
import Testing
@testable import Domain
@testable import Lyrics

@Suite("LyricsService")
struct LyricsServiceTests {
    @Test("returns cached result on cache hit")
    func cacheHit() async {
        let expected = LyricsResult(id: 1, syncedLyrics: "[00:01.00] Hello")

        await withDependencies {
            $0.lyricsCache = MockLyricsCache(stored: expected)
            $0.lyricsRepository = MockLyricsRepository(result: nil)
        } operation: {
            let service = LyricsService()
            let result = await service.fetch(title: "Test", artist: "Artist", duration: nil)
            #expect(result.id == 1)
        }
    }

    @Test("fetches from remote on cache miss")
    func remoteFetch() async {
        let expected = LyricsResult(id: 2, syncedLyrics: "[00:01.00] World")

        await withDependencies {
            $0.lyricsCache = MockLyricsCache(stored: nil)
            $0.lyricsRepository = MockLyricsRepository(result: expected)
        } operation: {
            let service = LyricsService()
            let result = await service.fetch(title: "Test", artist: "Artist", duration: nil)
            #expect(result.id == 2)
        }
    }

    @Test("returns empty when both miss")
    func bothMiss() async {
        await withDependencies {
            $0.lyricsCache = MockLyricsCache(stored: nil)
            $0.lyricsRepository = MockLyricsRepository(result: nil)
        } operation: {
            let service = LyricsService()
            let result = await service.fetch(title: "Unknown", artist: "Nobody", duration: nil)
            #expect(result == .empty)
        }
    }

    @Test("skips cache for empty artist")
    func emptyArtistSkipsCache() async {
        let remote = LyricsResult(id: 3, plainLyrics: "Line 1")
        await withDependencies {
            $0.lyricsCache = MockLyricsCache(stored: LyricsResult(id: 999))
            $0.lyricsRepository = MockLyricsRepository(result: remote)
        } operation: {
            let service = LyricsService()
            let result = await service.fetch(title: "Test", artist: "", duration: nil)
            #expect(result.id == 3)
        }
    }
}

// MARK: - Mocks

private struct MockLyricsCache: LyricsCacheRepository {
    let stored: LyricsResult?
    var written: [LyricsResult] = []

    func read(title: String, artist: String) async -> LyricsResult? { stored }
    func write(title: String, artist: String, result: LyricsResult) async throws {}
}

private struct MockLyricsRepository: LyricsRepository {
    let result: LyricsResult?

    func fetch(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? { result }
}
