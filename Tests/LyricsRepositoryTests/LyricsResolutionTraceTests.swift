import Dependencies
import Domain
import Foundation
import Testing
import os

@testable import LyricsRepository

@Suite("LyricsResolution trace (#331)")
struct LyricsResolutionTraceTests {
    @Test("a disabled log records nothing and does not change the result")
    func disabledRecordsNothing() async {
        let spy = SpyResolutionLog(enabled: false)
        let hit = LyricsResult(
            id: 1, trackName: "Song", artistName: "Artist", duration: 200, syncedLyrics: "[00:01.00] hi")
        let result = await withDependencies {
            $0.lyricsCache = EmptyCache()
            $0.lyricsDataSource = GetStub(result: hit)
            $0.lyricsResolutionLog = spy
        } operation: {
            await LyricsRepositoryImpl().fetchLyrics(candidates: [Track(title: "Song", artist: "Artist", duration: 200)])
        }
        #expect(result != nil)
        #expect(spy.records.isEmpty)
    }

    @Test("a Tier A success records candidates, the accept, and the outcome")
    func tierASuccessTrace() async {
        let spy = SpyResolutionLog(enabled: true)
        let hit = LyricsResult(
            id: 1, trackName: "Song", artistName: "Artist", duration: 200, syncedLyrics: "[00:01.00] hi")
        _ = await withDependencies {
            $0.lyricsCache = EmptyCache()
            $0.lyricsDataSource = GetStub(result: hit)
            $0.lyricsResolutionLog = spy
        } operation: {
            await LyricsRepositoryImpl().fetchLyrics(candidates: [Track(title: "Song", artist: "Artist", duration: 200)])
        }
        #expect(spy.records.count == 1)
        let block = spy.records.first ?? ""
        #expect(block.contains("candidates:"))
        #expect(block.contains("tierA"))
        #expect(block.contains("ACCEPT"))
        #expect(block.contains("result: tierA"))
    }

    @Test("a Tier B duration mismatch is recorded with its reject reason (the cover case)")
    func tierBDurationRejectTrace() async {
        // Cover case: the only lyric-bearing search hit is the original recording at a
        // different duration, so validation rejects it — the trace states exactly why.
        let spy = SpyResolutionLog(enabled: true)
        let original = LyricsResult(
            id: 9, trackName: "Yesterday", artistName: "The Beatles", duration: 125, syncedLyrics: "[00:01.00] hi")
        let result = await withDependencies {
            $0.lyricsCache = EmptyCache()
            $0.lyricsDataSource = SearchOnlyStub(searchResult: [original])
            $0.lyricsResolutionLog = spy
        } operation: {
            await LyricsRepositoryImpl().fetchLyrics(
                candidates: [Track(title: "Yesterday", artist: "The Beatles", duration: 180)])
        }
        #expect(result == nil)
        let joined = spy.records.joined(separator: "\n")
        #expect(joined.contains("tierB"))
        #expect(joined.contains("REJECT"))
        #expect(joined.contains("durΔ"))
        #expect(joined.contains("result: none"))
    }

    @Test("an enabled log records a cache hit and the cache outcome")
    func cacheHitTrace() async {
        let spy = SpyResolutionLog(enabled: true)
        let cached = LyricsResult(
            id: 1, trackName: "Song", artistName: "Artist", duration: 200, syncedLyrics: "[00:01.00] hi")
        let result = await withDependencies {
            $0.lyricsCache = CacheStub(entry: cached)
            $0.lyricsDataSource = GetStub(result: nil)
            $0.lyricsResolutionLog = spy
        } operation: {
            await LyricsRepositoryImpl().fetchLyrics(candidates: [Track(title: "Song", artist: "Artist", duration: 200)])
        }
        #expect(result != nil)
        let joined = spy.records.joined(separator: "\n")
        #expect(joined.contains("cache HIT"))
        #expect(joined.contains("result: cache"))
    }

    @Test("an enabled log records a cache reject with its reason, then falls through")
    func cacheRejectTrace() async {
        // A row cached under the same title but a mismatched duration fails validation,
        // so the trace states the reject reason and resolution falls through to the tiers.
        let spy = SpyResolutionLog(enabled: true)
        let poisoned = LyricsResult(
            id: 2, trackName: "Song", artistName: "Artist", duration: 125, syncedLyrics: "[00:01.00] hi")
        let result = await withDependencies {
            $0.lyricsCache = CacheStub(entry: poisoned)
            $0.lyricsDataSource = GetStub(result: nil)
            $0.lyricsResolutionLog = spy
        } operation: {
            await LyricsRepositoryImpl().fetchLyrics(candidates: [Track(title: "Song", artist: "Artist", duration: 180)])
        }
        #expect(result == nil)
        let joined = spy.records.joined(separator: "\n")
        #expect(joined.contains("cache REJECT"))
        #expect(joined.contains("durΔ"))
    }

    @Test("an enabled log records a tierB miss when the responses carry no lyrics")
    func tierBNoLyricBearingTrace() async {
        // Search returns a response with neither synced nor plain lyrics — no lyric-bearing
        // result to validate, so the miss reason names the empty-response case.
        let spy = SpyResolutionLog(enabled: true)
        let empty = LyricsResult(id: 3, trackName: "Song", artistName: "Artist", duration: 200)
        let result = await withDependencies {
            $0.lyricsCache = EmptyCache()
            $0.lyricsDataSource = SearchOnlyStub(searchResult: [empty])
            $0.lyricsResolutionLog = spy
        } operation: {
            await LyricsRepositoryImpl().fetchLyrics(candidates: [Track(title: "Song", artist: "Artist", duration: 200)])
        }
        #expect(result == nil)
        let joined = spy.records.joined(separator: "\n")
        #expect(joined.contains("no lyric-bearing result"))
    }

    @Test("an enabled log records a tierB accept and the tierB outcome")
    func tierBSuccessTrace() async {
        let spy = SpyResolutionLog(enabled: true)
        let match = LyricsResult(
            id: 5, trackName: "Song", artistName: "Artist", duration: 200, syncedLyrics: "[00:01.00] hi")
        let result = await withDependencies {
            $0.lyricsCache = EmptyCache()
            $0.lyricsDataSource = SearchOnlyStub(searchResult: [match])
            $0.lyricsResolutionLog = spy
        } operation: {
            await LyricsRepositoryImpl().fetchLyrics(candidates: [Track(title: "Song", artist: "Artist", duration: 200)])
        }
        #expect(result != nil)
        let joined = spy.records.joined(separator: "\n")
        #expect(joined.contains("tierB"))
        #expect(joined.contains("ACCEPT"))
        #expect(joined.contains("result: tierB"))
    }

    @Test("an enabled log records a tierC accept and the tierC outcome")
    func tierCSuccessTrace() async {
        let spy = SpyResolutionLog(enabled: true)
        let match = LyricsResult(
            id: 6, trackName: "Song", artistName: "Artist", duration: 200, syncedLyrics: "[00:01.00] hi")
        let result = await withDependencies {
            $0.lyricsCache = EmptyCache()
            $0.lyricsDataSource = GetStub(result: nil)
            $0.customScriptLyricsDataSource = GetStub(result: match)
            $0.lyricsResolutionLog = spy
        } operation: {
            await LyricsRepositoryImpl().fetchLyrics(candidates: [Track(title: "Song", artist: "Artist", duration: 200)])
        }
        #expect(result != nil)
        let joined = spy.records.joined(separator: "\n")
        #expect(joined.contains("tierC"))
        #expect(joined.contains("ACCEPT"))
        #expect(joined.contains("result: tierC"))
    }

    @Test("a tierA result with no track/artist names falls back to the candidate identity")
    func tierANilNamesTrace() async {
        // Tier A trusts LRCLIB as-is; when the result omits track/artist names,
        // displayAdjusted fills them from the candidate.
        let spy = SpyResolutionLog(enabled: true)
        let hit = LyricsResult(id: 7, trackName: nil, artistName: nil, duration: 200, syncedLyrics: "[00:01.00] hi")
        let result = await withDependencies {
            $0.lyricsCache = EmptyCache()
            $0.lyricsDataSource = GetStub(result: hit)
            $0.lyricsResolutionLog = spy
        } operation: {
            await LyricsRepositoryImpl().fetchLyrics(candidates: [Track(title: "Song", artist: "Artist", duration: 200)])
        }
        #expect(result?.trackName == "Song")
        #expect(result?.artistName == "Artist")
    }

    @Test("empty (not nil) result names also fall back to the candidate identity")
    func tierAEmptyNamesTrace() async {
        // trackName/artistName present but empty strings → displayAdjusted still falls
        // back to the candidate; the trace describes the no-lyrics result as [none].
        let spy = SpyResolutionLog(enabled: true)
        let hit = LyricsResult(id: 10, trackName: "", artistName: "", duration: 200)
        let result = await withDependencies {
            $0.lyricsCache = EmptyCache()
            $0.lyricsDataSource = GetStub(result: hit)
            $0.lyricsResolutionLog = spy
        } operation: {
            await LyricsRepositoryImpl().fetchLyrics(candidates: [Track(title: "Song", artist: "Artist", duration: 200)])
        }
        #expect(result?.trackName == "Song")
        #expect(result?.artistName == "Artist")
        #expect(spy.records.joined(separator: "\n").contains("[none]"))
    }

    @Test("an enabled log builds a title-only query for a candidate with no artist")
    func tierBEmptyArtistQueryTrace() async {
        let spy = SpyResolutionLog(enabled: true)
        let result = await withDependencies {
            $0.lyricsCache = EmptyCache()
            $0.lyricsDataSource = SearchOnlyStub(searchResult: nil)
            $0.lyricsResolutionLog = spy
        } operation: {
            await LyricsRepositoryImpl().fetchLyrics(candidates: [Track(title: "Song", artist: "", duration: 200)])
        }
        #expect(result == nil)
        #expect(spy.records.joined(separator: "\n").contains("search 'Song'"))
    }

    @Test("an enabled log shows durΔ=n/a and [plain] for a reject with no duration and plain lyrics")
    func tierCRejectNoDurationTrace() async {
        let spy = SpyResolutionLog(enabled: true)
        let wrongTitle = LyricsResult(
            id: 8, trackName: "Totally Different", artistName: "Artist", duration: 200, plainLyrics: "words")
        let result = await withDependencies {
            $0.lyricsCache = EmptyCache()
            $0.lyricsDataSource = GetStub(result: nil)
            $0.customScriptLyricsDataSource = GetStub(result: wrongTitle)
            $0.lyricsResolutionLog = spy
        } operation: {
            await LyricsRepositoryImpl().fetchLyrics(candidates: [Track(title: "Song", artist: "Artist", duration: nil)])
        }
        #expect(result == nil)
        let joined = spy.records.joined(separator: "\n")
        #expect(joined.contains("durΔ=n/a"))
        #expect(joined.contains("[plain]"))
    }

    @Test("an enabled log shows titleSim=n/a for a reject whose result has no track name")
    func tierCRejectNoTitleTrace() async {
        let spy = SpyResolutionLog(enabled: true)
        let noTitle = LyricsResult(id: 9, trackName: nil, artistName: "Artist", duration: 125, plainLyrics: "words")
        let result = await withDependencies {
            $0.lyricsCache = EmptyCache()
            $0.lyricsDataSource = GetStub(result: nil)
            $0.customScriptLyricsDataSource = GetStub(result: noTitle)
            $0.lyricsResolutionLog = spy
        } operation: {
            await LyricsRepositoryImpl().fetchLyrics(candidates: [Track(title: "Song", artist: "Artist", duration: 180)])
        }
        #expect(result == nil)
        #expect(spy.records.joined(separator: "\n").contains("titleSim=n/a"))
    }

    @Test("an enabled log records a tierC script reject with its reason")
    func tierCRejectTrace() async {
        // Tier A/B miss; the Tier C script returns lyrics for a mismatched duration, so
        // validation rejects it and the trace records the tierC reject.
        let spy = SpyResolutionLog(enabled: true)
        let scriptResult = LyricsResult(
            id: 4, trackName: "Song", artistName: "Artist", duration: 125, syncedLyrics: "[00:01.00] hi")
        let result = await withDependencies {
            $0.lyricsCache = EmptyCache()
            $0.lyricsDataSource = GetStub(result: nil)
            $0.customScriptLyricsDataSource = GetStub(result: scriptResult)
            $0.lyricsResolutionLog = spy
        } operation: {
            await LyricsRepositoryImpl().fetchLyrics(candidates: [Track(title: "Song", artist: "Artist", duration: 180)])
        }
        #expect(result == nil)
        let joined = spy.records.joined(separator: "\n")
        #expect(joined.contains("tierC"))
        #expect(joined.contains("REJECT"))
    }
}

private struct EmptyCache: LyricsDataStore {
    func read(title: String, artist: String) async -> LyricsResult? { nil }
    func write(title: String, artist: String, result: LyricsResult) async throws {}
}

private struct CacheStub: LyricsDataStore {
    let entry: LyricsResult?
    func read(title: String, artist: String) async -> LyricsResult? { entry }
    func write(title: String, artist: String, result: LyricsResult) async throws {}
}

private struct GetStub: LyricsDataSource {
    let result: LyricsResult?
    func get(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? { result }
    func search(query: String) async -> [LyricsResult]? { nil }
}

private struct SearchOnlyStub: LyricsDataSource {
    let searchResult: [LyricsResult]?
    func get(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? { nil }
    func search(query: String) async -> [LyricsResult]? { searchResult }
}

private final class SpyResolutionLog: DeveloperLog {
    let enabled: Bool
    private let recorded = OSAllocatedUnfairLock(initialState: [String]())
    init(enabled: Bool) { self.enabled = enabled }
    var isEnabled: Bool { enabled }
    var records: [String] { recorded.withLock { $0 } }
    func record(_ text: String) { recorded.withLock { $0.append(text) } }
}
