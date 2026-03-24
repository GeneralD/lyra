import Dependencies
import Domain
import Foundation
import Testing

@testable import LyricsRepository

@Suite("LyricsRepository")
struct LyricsRepositoryTests {

    @Suite("cache behavior")
    struct CacheBehavior {
        @Test("cache hit returns cached result without calling DataSource")
        func cacheHitReturns() async {
            let cached = LyricsResult(
                trackName: "Cached Title", artistName: "Cached Artist",
                syncedLyrics: "[00:01.00] Hello"
            )

            await withDependencies {
                $0.lyricsCache = StubLyricsCache(stored: cached)
            } operation: {
                let repo = LyricsRepositoryImpl()
                let result = await repo.fetchLyrics(track: Track(title: "any", artist: "any"))
                #expect(result?.trackName == "Cached Title")
                #expect(result?.syncedLyrics == "[00:01.00] Hello")
            }
        }

        @Test("cache hit with candidates returns cached result")
        func cacheHitWithCandidates() async {
            let cached = LyricsResult(syncedLyrics: "[00:01.00] Cached")

            await withDependencies {
                $0.lyricsCache = StubLyricsCache(stored: cached)
            } operation: {
                let repo = LyricsRepositoryImpl()
                let result = await repo.fetchLyrics(candidates: [
                    Track(title: "First", artist: "Artist"),
                    Track(title: "Second", artist: "Artist"),
                ])
                #expect(result?.syncedLyrics == "[00:01.00] Cached")
            }
        }

        @Test("cache miss returns nil when no lyrics found")
        func cacheMissNoLyrics() async {
            await withDependencies {
                $0.lyricsCache = StubLyricsCache(stored: nil)
            } operation: {
                let repo = LyricsRepositoryImpl()
                let result = await repo.fetchLyrics(
                    track: Track(title: "zzz_nonexistent_zzz", artist: "zzz_nobody_zzz")
                )
                #expect(result == nil)
            }
        }

        @Test("empty candidates returns nil")
        func emptyCandidates() async {
            await withDependencies {
                $0.lyricsCache = StubLyricsCache(stored: nil)
            } operation: {
                let repo = LyricsRepositoryImpl()
                let result = await repo.fetchLyrics(candidates: [])
                #expect(result == nil)
            }
        }
    }
}

// MARK: - Test helpers

private struct StubLyricsCache: LyricsDataStore {
    let stored: LyricsResult?
    func read(title: String, artist: String) async -> LyricsResult? { stored }
    func write(title: String, artist: String, result: LyricsResult) async throws {}
}
