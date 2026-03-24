import Dependencies
import Domain
import Foundation
import Testing

@testable import LyricsRepository

@Suite("LyricsRepository edge cases")
struct LyricsRepositoryEdgeCaseTests {

    // MARK: - fetchLyrics(track:) tests

    @Test("cache miss with synced lyrics from dataSource writes to cache and returns result")
    func cacheMissDataSourceGetSyncedWritesToCache() async {
        let expected = LyricsResult(trackName: "Song", artistName: "Band", syncedLyrics: "[00:01.00] Hello")
        let cache = TrackingLyricsCache(stored: nil)

        await withDependencies {
            $0.lyricsCache = cache
            $0.lyricsDataSource = MockLyricsDataSource(getResult: expected)
        } operation: {
            let repo = LyricsRepositoryImpl()
            let result = await repo.fetchLyrics(track: Track(title: "Song", artist: "Band"))
            #expect(result == expected)
            let writeCount = await cache.writeCallCount
            #expect(writeCount == 1)
        }
    }

    @Test("cache miss with plain-only lyrics from dataSource still returns result")
    func cacheMissDataSourceGetPlainLyricsReturns() async {
        let plainOnly = LyricsResult(plainLyrics: "Just plain text")

        await withDependencies {
            $0.lyricsCache = TrackingLyricsCache(stored: nil)
            $0.lyricsDataSource = MockLyricsDataSource(getResult: plainOnly)
        } operation: {
            let repo = LyricsRepositoryImpl()
            let result = await repo.fetchLyrics(track: Track(title: "Song", artist: "Band"))
            #expect(result?.plainLyrics == "Just plain text")
            #expect(result?.syncedLyrics == nil)
        }
    }

    @Test("cache miss with empty artist does NOT write to cache")
    func emptyArtistDoesNotWriteToCache() async {
        let result = LyricsResult(syncedLyrics: "[00:01.00] Hello")
        let cache = TrackingLyricsCache(stored: nil)

        await withDependencies {
            $0.lyricsCache = cache
            $0.lyricsDataSource = MockLyricsDataSource(getResult: result)
        } operation: {
            let repo = LyricsRepositoryImpl()
            let fetched = await repo.fetchLyrics(track: Track(title: "Song", artist: ""))
            #expect(fetched != nil)
            let writeCount = await cache.writeCallCount
            #expect(writeCount == 0)
        }
    }

    @Test("search fallback with empty artist uses title-only query")
    func searchFallbackEmptyArtistUsesTitle() async {
        let searchResult = LyricsResult(syncedLyrics: "[00:01.00] Found via search")
        let capturingDS = QueryCapturingDataSource(searchResults: [searchResult])

        await withDependencies {
            $0.lyricsCache = TrackingLyricsCache(stored: nil)
            $0.lyricsDataSource = capturingDS
        } operation: {
            let repo = LyricsRepositoryImpl()
            let result = await repo.fetchLyrics(track: Track(title: "MyTitle", artist: ""))
            #expect(result?.syncedLyrics == "[00:01.00] Found via search")
            let query = await capturingDS.lastSearchQuery
            #expect(query == "MyTitle")
        }
    }

    @Test("search fallback prefers syncedLyrics over plain-only results")
    func searchPrefersSyncedOverPlain() async {
        let plainResult = LyricsResult(plainLyrics: "Plain only")
        let syncedResult = LyricsResult(syncedLyrics: "[00:01.00] Synced")

        await withDependencies {
            $0.lyricsCache = TrackingLyricsCache(stored: nil)
            $0.lyricsDataSource = MockLyricsDataSource(
                getResult: nil,
                searchResults: [plainResult, syncedResult]
            )
        } operation: {
            let repo = LyricsRepositoryImpl()
            let result = await repo.fetchLyrics(track: Track(title: "Song", artist: "Band"))
            #expect(result?.syncedLyrics == "[00:01.00] Synced")
        }
    }

    // MARK: - fetchLyrics(candidates:) tests

    @Test("candidates with empty artist are skipped in get phase")
    func candidatesSkipsEmptyArtistInGetPhase() async {
        let expected = LyricsResult(syncedLyrics: "[00:01.00] Found")

        await withDependencies {
            $0.lyricsCache = TrackingLyricsCache(stored: nil)
            $0.lyricsDataSource = ArtistFilteringDataSource(result: expected)
        } operation: {
            let repo = LyricsRepositoryImpl()
            let result = await repo.fetchLyrics(candidates: [
                Track(title: "Title1", artist: ""),
                Track(title: "Title2", artist: "ValidArtist"),
            ])
            #expect(result?.syncedLyrics == "[00:01.00] Found")
        }
    }

    @Test("candidates applies withDisplay from first candidate")
    func candidatesAppliesWithDisplayFromFirst() async {
        let raw = LyricsResult(trackName: "Raw", artistName: "RawArtist", syncedLyrics: "[00:01.00] Line")

        await withDependencies {
            $0.lyricsCache = TrackingLyricsCache(stored: nil)
            $0.lyricsDataSource = MockLyricsDataSource(getResult: raw)
        } operation: {
            let repo = LyricsRepositoryImpl()
            let result = await repo.fetchLyrics(candidates: [
                Track(title: "Display Title", artist: "Display Artist"),
                Track(title: "Alt", artist: "AltArtist"),
            ])
            #expect(result?.trackName == "Display Title")
            #expect(result?.artistName == "Display Artist")
            #expect(result?.syncedLyrics == "[00:01.00] Line")
        }
    }

    @Test("candidates search fallback across all candidates")
    func candidatesSearchFallbackAcrossAll() async {
        let searchResult = LyricsResult(syncedLyrics: "[00:01.00] Search hit")

        await withDependencies {
            $0.lyricsCache = TrackingLyricsCache(stored: nil)
            $0.lyricsDataSource = SecondQueryMatchDataSource(matchResult: searchResult)
        } operation: {
            let repo = LyricsRepositoryImpl()
            let result = await repo.fetchLyrics(candidates: [
                Track(title: "NoMatch", artist: "A"),
                Track(title: "Match", artist: "B"),
            ])
            #expect(result?.syncedLyrics == "[00:01.00] Search hit")
        }
    }
}

// MARK: - Mocks

private struct MockLyricsDataSource: LyricsDataSource {
    var getResult: LyricsResult?
    var searchResults: [LyricsResult]?
    func get(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? { getResult }
    func search(query: String) async -> [LyricsResult]? { searchResults }
}

private actor TrackingLyricsCache: LyricsDataStore {
    var stored: LyricsResult?
    private(set) var writeCallCount = 0

    init(stored: LyricsResult?) {
        self.stored = stored
    }

    func read(title: String, artist: String) async -> LyricsResult? { stored }
    func write(title: String, artist: String, result: LyricsResult) async throws {
        writeCallCount += 1
    }
}

private actor QueryCapturingDataSource: LyricsDataSource {
    let searchResults: [LyricsResult]?
    private(set) var lastSearchQuery: String?

    init(searchResults: [LyricsResult]?) {
        self.searchResults = searchResults
    }

    func get(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? { nil }
    func search(query: String) async -> [LyricsResult]? {
        lastSearchQuery = query
        return searchResults
    }
}

private struct ArtistFilteringDataSource: LyricsDataSource {
    let result: LyricsResult
    func get(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? {
        guard !artist.isEmpty else { return nil }
        return result
    }
    func search(query: String) async -> [LyricsResult]? { nil }
}

private struct SecondQueryMatchDataSource: LyricsDataSource {
    let matchResult: LyricsResult
    func get(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? { nil }
    func search(query: String) async -> [LyricsResult]? {
        guard query.contains("Match") else { return nil }
        return [matchResult]
    }
}
