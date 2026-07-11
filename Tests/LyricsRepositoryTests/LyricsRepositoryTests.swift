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

        @Test("falls back to uta-net when LRCLIB get and search both miss")
        func utaNetFallbackOnSingleTrack() async {
            let utaNetResult = LyricsResult(trackName: "Song", artistName: "Artist", plainLyrics: "uta-net lyrics")

            await withDependencies {
                $0.lyricsCache = StubLyricsCache(stored: nil)
                $0.lyricsDataSource = StubLyricsDataSource(getResult: nil, searchResult: nil)
                $0.utaNetLyricsDataSource = StubLyricsDataSource(getResult: utaNetResult)
            } operation: {
                let repo = LyricsRepositoryImpl()
                let result = await repo.fetchLyrics(
                    track: Track(title: "Song", artist: "Artist"))
                #expect(result?.plainLyrics == "uta-net lyrics")
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

        @Test("matched candidate's display name is preserved, not overridden by first candidate")
        func preservesMatchedCandidateDisplay() async {
            let lrclibResult = LyricsResult(
                trackName: "Resolved Title", artistName: "Resolved Artist",
                plainLyrics: "Lyrics body"
            )

            await withDependencies {
                $0.lyricsCache = StubLyricsCache(stored: nil)
                $0.lyricsDataSource = StubLyricsDataSource(
                    getHandler: { _, artist, _ in
                        artist == "Real Artist" ? lrclibResult : nil
                    })
            } operation: {
                let repo = LyricsRepositoryImpl()
                let result = await repo.fetchLyrics(candidates: [
                    Track(title: "Garbled Title", artist: "Garbled Artist"),
                    Track(title: "Real Title", artist: "Real Artist"),
                ])
                #expect(result?.trackName == "Resolved Title")
                #expect(result?.artistName == "Resolved Artist")
                #expect(result?.plainLyrics == "Lyrics body")
            }
        }

        @Test("falls back to matched candidate's title/artist when LRCLIB returns empty trackName")
        func fallsBackToMatchedCandidate() async {
            let lrclibResult = LyricsResult(plainLyrics: "Lyrics body")

            await withDependencies {
                $0.lyricsCache = StubLyricsCache(stored: nil)
                $0.lyricsDataSource = StubLyricsDataSource(
                    getHandler: { _, artist, _ in
                        artist == "Real Artist" ? lrclibResult : nil
                    })
            } operation: {
                let repo = LyricsRepositoryImpl()
                let result = await repo.fetchLyrics(candidates: [
                    Track(title: "Garbled Title", artist: "Garbled Artist"),
                    Track(title: "Real Title", artist: "Real Artist"),
                ])
                #expect(result?.trackName == "Real Title")
                #expect(result?.artistName == "Real Artist")
            }
        }

        @Test("Tier A cache write is keyed by the matched candidate, not candidates.first")
        func cacheWriteKeyedByMatchedCandidateTierA() async {
            let lrclibResult = LyricsResult(plainLyrics: "Lyrics body")
            let spy = KeyCapturingLyricsCache()

            await withDependencies {
                $0.lyricsCache = spy
                $0.lyricsDataSource = StubLyricsDataSource(
                    getHandler: { _, artist, _ in
                        artist == "Real Artist" ? lrclibResult : nil
                    })
            } operation: {
                let repo = LyricsRepositoryImpl()
                _ = await repo.fetchLyrics(candidates: [
                    Track(title: "Garbled Title", artist: "Garbled Artist"),
                    Track(title: "Real Title", artist: "Real Artist"),
                ])
                let key = await spy.lastWriteKey
                #expect(key?.title == "Real Title")
                #expect(key?.artist == "Real Artist")
            }
        }

        @Test("Tier B (search) validates title similarity and caches under the matched candidate")
        func tierBValidatesAndCachesMatchedCandidate() async {
            let validResult = LyricsResult(trackName: "Real Title", artistName: "Real Artist", syncedLyrics: "[00:01.00] Line")
            let spy = KeyCapturingLyricsCache()

            await withDependencies {
                $0.lyricsCache = spy
                $0.lyricsDataSource = QueryMatchingSearchDataSource(
                    getResult: nil,
                    resultsByQuery: ["Real Title Real Artist": [validResult]]
                )
            } operation: {
                let repo = LyricsRepositoryImpl()
                let result = await repo.fetchLyrics(candidates: [
                    Track(title: "Garbled Title", artist: "Garbled Artist"),
                    Track(title: "Real Title", artist: "Real Artist"),
                ])
                #expect(result?.syncedLyrics == "[00:01.00] Line")
                let key = await spy.lastWriteKey
                #expect(key?.title == "Real Title")
                #expect(key?.artist == "Real Artist")
            }
        }

        @Test("Tier B rejects a search result whose title is wildly different from the candidate")
        func tierBRejectsMismatchedTitle() async {
            let mismatchedResult = LyricsResult(trackName: "Completely Different Song", artistName: "Someone Else", plainLyrics: "wrong lyrics")

            await withDependencies {
                $0.lyricsCache = StubLyricsCache(stored: nil)
                $0.lyricsDataSource = QueryMatchingSearchDataSource(
                    getResult: nil,
                    resultsByQuery: ["My Title My Artist": [mismatchedResult]]
                )
            } operation: {
                let repo = LyricsRepositoryImpl()
                let result = await repo.fetchLyrics(candidates: [
                    Track(title: "My Title", artist: "My Artist")
                ])
                #expect(result == nil, "a title-mismatched search result must not be accepted")
            }
        }

        @Test("Tier B validates every fuzzy hit — a noisy leading result does not sink a valid later one")
        func tierBValidatesAllSearchResults() async {
            let noise = LyricsResult(trackName: "Completely Unrelated Noise", artistName: "Nobody", plainLyrics: "noise")
            let valid = LyricsResult(trackName: "My Title", artistName: "My Artist", syncedLyrics: "[00:01.00] Real")

            await withDependencies {
                $0.lyricsCache = StubLyricsCache(stored: nil)
                $0.lyricsDataSource = QueryMatchingSearchDataSource(
                    getResult: nil,
                    resultsByQuery: ["My Title My Artist": [noise, valid]]
                )
            } operation: {
                let repo = LyricsRepositoryImpl()
                let result = await repo.fetchLyrics(candidates: [
                    Track(title: "My Title", artist: "My Artist")
                ])
                #expect(
                    result?.syncedLyrics == "[00:01.00] Real",
                    "the valid later hit must be accepted even though a noisy result came first")
            }
        }

        @Test("Tier C (uta-net) is tried after Tier A/B fail, and its result is cached under the matched candidate")
        func tierCUtaNetFallsBackAndCaches() async {
            let utaNetResult = LyricsResult(trackName: "Real Title", artistName: "Real Artist", plainLyrics: "uta-net lyrics")
            let spy = KeyCapturingLyricsCache()

            await withDependencies {
                $0.lyricsCache = spy
                $0.lyricsDataSource = StubLyricsDataSource(getResult: nil, searchResult: nil)
                $0.utaNetLyricsDataSource = StubLyricsDataSource(
                    getHandler: { _, artist, _ in
                        artist == "Real Artist" ? utaNetResult : nil
                    })
                $0.customScriptLyricsDataSource = StubLyricsDataSource(
                    getResult: LyricsResult(trackName: "Real Title", plainLyrics: "script lyrics"))
            } operation: {
                let repo = LyricsRepositoryImpl()
                let result = await repo.fetchLyrics(candidates: [
                    Track(title: "Garbled Title", artist: "Garbled Artist"),
                    Track(title: "Real Title", artist: "Real Artist"),
                ])
                // uta-net (Tier C) must win over the custom script (Tier D).
                #expect(result?.plainLyrics == "uta-net lyrics")
                let key = await spy.lastWriteKey
                #expect(key?.title == "Real Title")
                #expect(key?.artist == "Real Artist")
            }
        }

        @Test("a full-width uta-net result validates against the half-width candidate")
        func tierCUtaNetFullWidthResultValidates() async {
            // uta-net returns its own listing spelling (often full-width); the
            // validator gate must not reject what the data source matched.
            let utaNetResult = LyricsResult(trackName: "Ｑ＆Ａ", artistName: "ＹＯＡＳＯＢＩ", plainLyrics: "uta-net lyrics")

            await withDependencies {
                $0.lyricsCache = StubLyricsCache(stored: nil)
                $0.lyricsDataSource = StubLyricsDataSource(getResult: nil, searchResult: nil)
                $0.utaNetLyricsDataSource = StubLyricsDataSource(getResult: utaNetResult, searchResult: nil)
            } operation: {
                let repo = LyricsRepositoryImpl()
                let result = await repo.fetchLyrics(candidates: [
                    Track(title: "Q&A", artist: "YOASOBI")
                ])
                #expect(result?.plainLyrics == "uta-net lyrics")
            }
        }

        @Test("a uta-net result failing validation falls through to Tier D (custom script)")
        func tierCUtaNetInvalidFallsThroughToScript() async {
            let mismatched = LyricsResult(
                trackName: "Completely Different Song", artistName: "Someone Else", plainLyrics: "wrong lyrics")
            let scriptResult = LyricsResult(trackName: "Real Title", artistName: "Real Artist", plainLyrics: "script lyrics")

            await withDependencies {
                $0.lyricsCache = StubLyricsCache(stored: nil)
                $0.lyricsDataSource = StubLyricsDataSource(getResult: nil, searchResult: nil)
                $0.utaNetLyricsDataSource = StubLyricsDataSource(getResult: mismatched, searchResult: nil)
                $0.customScriptLyricsDataSource = StubLyricsDataSource(getResult: scriptResult, searchResult: nil)
            } operation: {
                let repo = LyricsRepositoryImpl()
                let result = await repo.fetchLyrics(candidates: [
                    Track(title: "Real Title", artist: "Real Artist")
                ])
                #expect(result?.plainLyrics == "script lyrics")
            }
        }

        @Test("Tier D (custom script) is tried after Tier A/B/C fail, and its result is cached under the matched candidate")
        func tierDFallsBackAndCaches() async {
            let scriptResult = LyricsResult(trackName: "Real Title", artistName: "Real Artist", plainLyrics: "script lyrics")
            let spy = KeyCapturingLyricsCache()

            await withDependencies {
                $0.lyricsCache = spy
                $0.lyricsDataSource = StubLyricsDataSource(getResult: nil, searchResult: nil)
                $0.utaNetLyricsDataSource = StubLyricsDataSource(getResult: nil, searchResult: nil)
                $0.customScriptLyricsDataSource = StubLyricsDataSource(
                    getHandler: { _, artist, _ in
                        artist == "Real Artist" ? scriptResult : nil
                    })
            } operation: {
                let repo = LyricsRepositoryImpl()
                let result = await repo.fetchLyrics(candidates: [
                    Track(title: "Garbled Title", artist: "Garbled Artist"),
                    Track(title: "Real Title", artist: "Real Artist"),
                ])
                #expect(result?.plainLyrics == "script lyrics")
                let key = await spy.lastWriteKey
                #expect(key?.title == "Real Title")
                #expect(key?.artist == "Real Artist")
            }
        }

        @Test("cache read checks every candidate, not just candidates.first — a hit on a later candidate is found without touching any DataSource")
        func cacheReadChecksAllCandidates() async {
            let cached = LyricsResult(
                trackName: "Real Title", artistName: "Real Artist",
                syncedLyrics: "[00:01.00] Cached under second candidate"
            )

            await withDependencies {
                $0.lyricsCache = SingleKeyLyricsCache(
                    matchTitle: "Real Title", matchArtist: "Real Artist", result: cached)
                $0.lyricsDataSource = FailingLyricsDataSource()
                $0.utaNetLyricsDataSource = FailingLyricsDataSource()
                $0.customScriptLyricsDataSource = FailingLyricsDataSource()
            } operation: {
                let repo = LyricsRepositoryImpl()
                let result = await repo.fetchLyrics(candidates: [
                    Track(title: "Garbled Title", artist: "Garbled Artist"),
                    Track(title: "Real Title", artist: "Real Artist"),
                ])
                #expect(result?.syncedLyrics == "[00:01.00] Cached under second candidate")
            }
        }

        @Test("a cached entry whose track_name doesn't match the candidate is skipped — poisoned pre-validation rows can't short-circuit the tiers")
        func poisonedCacheEntryIsSkipped() async {
            let poisoned = LyricsResult(
                trackName: "Completely Unrelated Song", artistName: "Someone Else",
                syncedLyrics: "[00:01.00] Wrong lyrics")
            let fresh = LyricsResult(
                trackName: "Real Title", artistName: "Real Artist",
                syncedLyrics: "[00:01.00] Right lyrics")

            await withDependencies {
                $0.lyricsCache = StubLyricsCache(stored: poisoned)
                $0.lyricsDataSource = StubLyricsDataSource(getResult: fresh, searchResult: nil)
                $0.customScriptLyricsDataSource = StubLyricsDataSource(getResult: nil, searchResult: nil)
            } operation: {
                let repo = LyricsRepositoryImpl()
                let result = await repo.fetchLyrics(candidates: [
                    Track(title: "Real Title", artist: "Real Artist")
                ])
                #expect(result?.syncedLyrics == "[00:01.00] Right lyrics")
            }
        }

        @Test("a validated result missing artist_name takes the matched candidate's artist, not a mixed raw fallback")
        func missingArtistBackfilledFromCandidate() async {
            let scriptResult = LyricsResult(
                trackName: "Real Title", artistName: nil, plainLyrics: "La la la")

            await withDependencies {
                $0.lyricsCache = StubLyricsCache(stored: nil)
                $0.lyricsDataSource = StubLyricsDataSource(getResult: nil, searchResult: nil)
                $0.customScriptLyricsDataSource = StubLyricsDataSource(getResult: scriptResult, searchResult: nil)
            } operation: {
                let repo = LyricsRepositoryImpl()
                let result = await repo.fetchLyrics(candidates: [
                    Track(title: "Real Title", artist: "Candidate Artist")
                ])
                #expect(result?.trackName == "Real Title")
                #expect(result?.artistName == "Candidate Artist")
            }
        }

        @Test("no cache write occurs when Tier A/B/C/D all fail")
        func noCacheWriteWhenAllTiersFail() async {
            let spy = KeyCapturingLyricsCache()

            await withDependencies {
                $0.lyricsCache = spy
                $0.lyricsDataSource = StubLyricsDataSource(getResult: nil, searchResult: nil)
                $0.utaNetLyricsDataSource = StubLyricsDataSource(getResult: nil, searchResult: nil)
                $0.customScriptLyricsDataSource = StubLyricsDataSource(getResult: nil, searchResult: nil)
            } operation: {
                let repo = LyricsRepositoryImpl()
                let result = await repo.fetchLyrics(candidates: [
                    Track(title: "Title", artist: "Artist")
                ])
                #expect(result == nil)
                let key = await spy.lastWriteKey
                #expect(key == nil)
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

private actor KeyCapturingLyricsCache: LyricsDataStore {
    private(set) var lastWriteKey: (title: String, artist: String)?
    func read(title: String, artist: String) async -> LyricsResult? { nil }
    func write(title: String, artist: String, result: LyricsResult) async throws {
        lastWriteKey = (title, artist)
    }
}

private struct QueryMatchingSearchDataSource: LyricsDataSource {
    var getResult: LyricsResult?
    let resultsByQuery: [String: [LyricsResult]]

    func get(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? { getResult }
    func search(query: String) async -> [LyricsResult]? { resultsByQuery[query] }
}

private struct SingleKeyLyricsCache: LyricsDataStore {
    let matchTitle: String
    let matchArtist: String
    let result: LyricsResult

    func read(title: String, artist: String) async -> LyricsResult? {
        title == matchTitle && artist == matchArtist ? result : nil
    }
    func write(title: String, artist: String, result: LyricsResult) async throws {}
}

private struct FailingLyricsDataSource: LyricsDataSource {
    func get(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? {
        Issue.record("DataSource.get must not be called when a cache entry already satisfies the request")
        return nil
    }
    func search(query: String) async -> [LyricsResult]? {
        Issue.record("DataSource.search must not be called when a cache entry already satisfies the request")
        return nil
    }
}
