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

    @Suite("DataSource fetch")
    struct DataSourceFetch {
        @Test("direct get hit returns result and caches")
        func directGetHit() async {
            let expected = LyricsResult(plainLyrics: "Hello world")
            let spy = SpyLyricsCache()

            await withDependencies {
                $0.lyricsCache = spy
                $0.lyricsDataSource = StubLyricsDataSource(getResult: expected)
            } operation: {
                let repo = LyricsRepositoryImpl()
                let result = await repo.fetchLyrics(
                    track: Track(title: "Song", artist: "Artist"))
                #expect(result?.plainLyrics == "Hello world")
                #expect(spy.written)
            }
        }

        @Test("direct get miss falls through to search")
        func searchFallback() async {
            let searchResult = LyricsResult(syncedLyrics: "[00:01.00] Found via search")

            await withDependencies {
                $0.lyricsCache = StubLyricsCache(stored: nil)
                $0.lyricsDataSource = StubLyricsDataSource(
                    getResult: nil, searchResult: [searchResult])
            } operation: {
                let repo = LyricsRepositoryImpl()
                let result = await repo.fetchLyrics(
                    track: Track(title: "Song", artist: "Artist"))
                #expect(result?.syncedLyrics == "[00:01.00] Found via search")
            }
        }

        @Test("search prefers synced over plain lyrics")
        func searchPrefersSynced() async {
            let plain = LyricsResult(plainLyrics: "Plain only")
            let synced = LyricsResult(syncedLyrics: "[00:01.00] Synced")

            await withDependencies {
                $0.lyricsCache = StubLyricsCache(stored: nil)
                $0.lyricsDataSource = StubLyricsDataSource(
                    getResult: nil, searchResult: [plain, synced])
            } operation: {
                let repo = LyricsRepositoryImpl()
                let result = await repo.fetchLyrics(
                    track: Track(title: "Song", artist: "Artist"))
                #expect(result?.syncedLyrics != nil)
            }
        }

        @Test("empty artist uses title-only search query")
        func emptyArtistSearch() async {
            let searchResult = LyricsResult(plainLyrics: "Found")
            let spy = SpyLyricsDataSource(searchResult: [searchResult])

            await withDependencies {
                $0.lyricsCache = StubLyricsCache(stored: nil)
                $0.lyricsDataSource = spy
            } operation: {
                let repo = LyricsRepositoryImpl()
                let result = await repo.fetchLyrics(
                    track: Track(title: "Song", artist: ""))
                #expect(result?.plainLyrics == "Found")
                #expect(spy.searchQuery == "Song")
            }
        }

        @Test("does not cache when artist is empty")
        func noCacheForEmptyArtist() async {
            let expected = LyricsResult(plainLyrics: "Hello")
            let spy = SpyLyricsCache()

            await withDependencies {
                $0.lyricsCache = spy
                $0.lyricsDataSource = StubLyricsDataSource(getResult: expected)
            } operation: {
                let repo = LyricsRepositoryImpl()
                _ = await repo.fetchLyrics(
                    track: Track(title: "Song", artist: ""))
                #expect(!spy.written)
            }
        }
    }

    @Suite("candidates fetch")
    struct CandidatesFetch {
        @Test("iterates candidates until get hit")
        func iteratesCandidates() async {
            let expected = LyricsResult(plainLyrics: "Found for second")

            await withDependencies {
                $0.lyricsCache = StubLyricsCache(stored: nil)
                $0.lyricsDataSource = StubLyricsDataSource(
                    getHandler: { title, artist, _ in
                        artist == "Second" ? expected : nil
                    })
            } operation: {
                let repo = LyricsRepositoryImpl()
                let result = await repo.fetchLyrics(candidates: [
                    Track(title: "First", artist: "First"),
                    Track(title: "Second", artist: "Second"),
                ])
                #expect(result?.plainLyrics == "Found for second")
            }
        }

        @Test("skips candidates with empty artist in get phase")
        func skipsEmptyArtist() async {
            let expected = LyricsResult(plainLyrics: "Found")

            await withDependencies {
                $0.lyricsCache = StubLyricsCache(stored: nil)
                $0.lyricsDataSource = StubLyricsDataSource(
                    getHandler: { _, artist, _ in
                        artist == "Artist" ? expected : nil
                    })
            } operation: {
                let repo = LyricsRepositoryImpl()
                let result = await repo.fetchLyrics(candidates: [
                    Track(title: "NoArtist", artist: ""),
                    Track(title: "HasArtist", artist: "Artist"),
                ])
                #expect(result?.plainLyrics == "Found")
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

private final class SpyLyricsCache: LyricsDataStore, @unchecked Sendable {
    private(set) var written = false
    func read(title: String, artist: String) async -> LyricsResult? { nil }
    func write(title: String, artist: String, result: LyricsResult) async throws { written = true }
}

private struct StubLyricsDataSource: LyricsDataSource {
    var getResult: LyricsResult?
    var searchResult: [LyricsResult]?
    var getHandler: (@Sendable (String, String, TimeInterval?) -> LyricsResult?)?

    func get(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? {
        getHandler?(title, artist, duration) ?? getResult
    }
    func search(query: String) async -> [LyricsResult]? { searchResult }
}

private final class SpyLyricsDataSource: LyricsDataSource, @unchecked Sendable {
    var searchResult: [LyricsResult]?
    private(set) var searchQuery: String?

    init(searchResult: [LyricsResult]? = nil) { self.searchResult = searchResult }

    func get(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? { nil }
    func search(query: String) async -> [LyricsResult]? {
        searchQuery = query
        return searchResult
    }
}
