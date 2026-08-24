import Dependencies
import Domain
import Foundation
import Testing

@testable import LyricsRepository

@Suite("Tier B search form and synced trust (#343)")
struct LyricsTierBSearchTests {

    private func resolve(
        _ candidate: Track,
        dataSource: any LyricsDataSource,
        script: any LyricsDataSource = NeverCalledScript()
    ) async -> LyricsResult? {
        await withDependencies {
            $0.lyricsCache = EmptyCache()
            $0.lyricsDataSource = dataSource
            $0.customScriptLyricsDataSource = script
        } operation: {
            await LyricsRepositoryImpl().fetchLyrics(candidates: [candidate])
        }
    }

    // MARK: - Which index is asked, and with what

    @Test("the structured index is asked first, and answering it means the free-text one is never asked")
    func structuredIndexShortCircuits() async {
        let hit = LyricsResult(trackName: "Song", artistName: "Band", duration: 200, plainLyrics: "lyrics")
        let spy = SearchSpy(byTrackName: [hit], byQuery: nil)

        let result = await resolve(Track(title: "Song", artist: "Band", duration: 200), dataSource: spy)

        #expect(result?.plainLyrics == "lyrics")
        #expect(await spy.trackNameQueries == ["Song"])
        #expect(await spy.freeTextQueries.isEmpty)
    }

    @Test("an empty structured answer still falls back — a narrow index is not a verdict")
    func emptyStructuredAnswerFallsBack() async {
        let hit = LyricsResult(trackName: "Song", artistName: "Band", duration: 200, plainLyrics: "lyrics")
        let spy = SearchSpy(byTrackName: [], byQuery: [hit])

        let result = await resolve(Track(title: "Song", artist: "Band", duration: 200), dataSource: spy)

        #expect(result?.plainLyrics == "lyrics")
        #expect(await spy.trackNameQueries == ["Song"])
        #expect(await spy.freeTextQueries == ["Song Band"])
    }

    @Test("a nil structured answer falls back to the free-text index")
    func nilStructuredAnswerFallsBack() async {
        let hit = LyricsResult(trackName: "Song", artistName: "Band", duration: 200, plainLyrics: "lyrics")
        let spy = SearchSpy(byTrackName: nil, byQuery: [hit])

        let result = await resolve(Track(title: "Song", artist: "Band", duration: 200), dataSource: spy)

        #expect(result?.plainLyrics == "lyrics")
        #expect(await spy.freeTextQueries == ["Song Band"])
    }

    @Test("the search key is the normalized title — cover decoration never reaches either index")
    func normalizedTitleIsTheSearchKey() async {
        let spy = SearchSpy(byTrackName: nil, byQuery: nil)

        _ = await resolve(
            Track(title: "Song 歌ってみた", artist: "Uploader", duration: 200),
            dataSource: spy,
            script: GetStub(result: nil)
        )

        #expect(await spy.trackNameQueries == ["Song"])
        #expect(await spy.freeTextQueries == ["Song Uploader"])
    }

    @Test("a title no catalog could hold is never searched, but is still offered to the user script")
    func screenedCandidateSkipsLRCLibButReachesTierC() async {
        let spy = SearchSpy(byTrackName: nil, byQuery: nil)
        let scripted = LyricsResult(trackName: "ドラム解説", artistName: "Channel", plainLyrics: "words")

        let result = await resolve(
            Track(title: "ドラム解説", artist: "Channel", duration: 200),
            dataSource: spy,
            script: GetStub(result: scripted)
        )

        #expect(result?.plainLyrics == "words")
        #expect(await spy.getCalls.isEmpty)
        #expect(await spy.trackNameQueries.isEmpty)
        #expect(await spy.freeTextQueries.isEmpty)
    }

    // MARK: - Synced lyrics are kept only when the timings can be trusted

    @Test("a result matched on the relaxed duration tolerance comes back as plain text")
    func farOffLengthDemotesSyncedLyrics() async {
        // 40s off: inside the exact-title tolerance (max(20, 240*0.3) = 72) so it validates,
        // but far outside the ±5s the timings would have to hold to scroll in step.
        let loose = LyricsResult(
            trackName: "Song", artistName: "Band", duration: 240,
            plainLyrics: "lyrics", syncedLyrics: "[00:01.00] lyrics")
        let spy = SearchSpy(byTrackName: [loose], byQuery: nil)

        let result = await resolve(Track(title: "Song", artist: "Band", duration: 200), dataSource: spy)

        #expect(result?.syncedLyrics == nil)
        #expect(result?.plainLyrics == "lyrics")
    }

    @Test("a result of the right length keeps its synced lyrics")
    func matchingLengthKeepsSyncedLyrics() async {
        let tight = LyricsResult(
            trackName: "Song", artistName: "Band", duration: 203,
            plainLyrics: "lyrics", syncedLyrics: "[00:01.00] lyrics")
        let spy = SearchSpy(byTrackName: [tight], byQuery: nil)

        let result = await resolve(Track(title: "Song", artist: "Band", duration: 200), dataSource: spy)

        #expect(result?.syncedLyrics == "[00:01.00] lyrics")
    }

    @Test("an unread duration is absent evidence, not a reason to demote")
    func unknownDurationKeepsSyncedLyrics() async {
        let untimed = LyricsResult(
            trackName: "Song", artistName: "Band", plainLyrics: "lyrics", syncedLyrics: "[00:01.00] lyrics")
        let spy = SearchSpy(byTrackName: [untimed], byQuery: nil)

        let result = await resolve(Track(title: "Song", artist: "Band", duration: 200), dataSource: spy)

        #expect(result?.syncedLyrics == "[00:01.00] lyrics")
    }

    @Test("among several valid answers the one whose timings can be trusted wins, even from behind")
    func trustworthyTimingsOutrankPositionInTheResponse() async {
        let loose = LyricsResult(
            trackName: "Song", artistName: "Band", duration: 240,
            plainLyrics: "loose", syncedLyrics: "[00:01.00] loose")
        let tight = LyricsResult(
            trackName: "Song", artistName: "Band", duration: 202,
            plainLyrics: "tight", syncedLyrics: "[00:01.00] tight")
        let spy = SearchSpy(byTrackName: [loose, tight], byQuery: nil)

        let result = await resolve(Track(title: "Song", artist: "Band", duration: 200), dataSource: spy)

        #expect(result?.syncedLyrics == "[00:01.00] tight")
    }

    @Test("Tier A demotes on the same rule — every tier hands results back through one path")
    func tierAAlsoDemotesUntrustworthySynced() async {
        let loose = LyricsResult(
            trackName: "Song", artistName: "Band", duration: 240,
            plainLyrics: "lyrics", syncedLyrics: "[00:01.00] lyrics")

        let result = await resolve(
            Track(title: "Song", artist: "Band", duration: 200), dataSource: GetStub(result: loose))

        #expect(result?.syncedLyrics == nil)
        #expect(result?.plainLyrics == "lyrics")
    }
}

// MARK: - Doubles

private actor SearchSpy: LyricsDataSource {
    private(set) var getCalls: [String] = []
    private(set) var trackNameQueries: [String] = []
    private(set) var freeTextQueries: [String] = []

    private let byTrackName: [LyricsResult]?
    private let byQuery: [LyricsResult]?

    init(byTrackName: [LyricsResult]?, byQuery: [LyricsResult]?) {
        self.byTrackName = byTrackName
        self.byQuery = byQuery
    }

    func get(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? {
        getCalls.append(title)
        return nil
    }

    func search(trackName: String) async -> [LyricsResult]? {
        trackNameQueries.append(trackName)
        return byTrackName
    }

    func search(query: String) async -> [LyricsResult]? {
        freeTextQueries.append(query)
        return byQuery
    }
}

private struct GetStub: LyricsDataSource {
    let result: LyricsResult?
    func get(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? { result }
    func search(trackName: String) async -> [LyricsResult]? { nil }
    func search(query: String) async -> [LyricsResult]? { nil }
}

private struct NeverCalledScript: LyricsDataSource {
    func get(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? {
        Issue.record("Tier C must not run once an earlier tier has answered")
        return nil
    }
    func search(trackName: String) async -> [LyricsResult]? { nil }
    func search(query: String) async -> [LyricsResult]? { nil }
}

private struct EmptyCache: LyricsDataStore {
    func read(title: String, artist: String) async -> LyricsResult? { nil }
    func write(title: String, artist: String, result: LyricsResult) async throws {}
}
