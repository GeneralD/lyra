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
}

private struct EmptyCache: LyricsDataStore {
    func read(title: String, artist: String) async -> LyricsResult? { nil }
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
