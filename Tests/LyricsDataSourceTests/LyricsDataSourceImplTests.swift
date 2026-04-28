import Domain
import Foundation
import Testing

@testable import LyricsDataSource

@Suite("LyricsDataSourceImpl")
struct LyricsDataSourceImplTests {
    @Test("default init() wires the Papyrus-generated LRCLibAPI")
    func defaultInitInstantiates() {
        // Just exercising init() to cover the production wiring.
        // We don't make a network call — only verify construction succeeds.
        _ = LyricsDataSourceImpl()
    }

    @Test("get returns decoded result when plain lyrics exist")
    func getReturnsDecodedResult() async {
        let dataSource = LyricsDataSourceImpl(
            api: LRCLibStub(
                get: { trackName, artistName, _ in
                    LyricsResult(trackName: trackName, artistName: artistName, plainLyrics: "I've become so numb")
                }
            )
        )

        let result = await dataSource.get(title: "Numb", artist: "Linkin Park", duration: 187)

        #expect(result?.trackName == "Numb")
        #expect(result?.artistName == "Linkin Park")
        #expect(result?.plainLyrics == "I've become so numb")
    }

    @Test("get returns nil when result has no lyrics")
    func getReturnsNilWithoutLyrics() async {
        let dataSource = LyricsDataSourceImpl(
            api: LRCLibStub(get: { _, _, _ in
                LyricsResult(trackName: "Song", artistName: "Artist", plainLyrics: nil, syncedLyrics: nil)
            })
        )

        let result = await dataSource.get(title: "Song", artist: "Artist", duration: nil)

        #expect(result == nil)
    }

    @Test("get returns result when only synced lyrics exist")
    func getReturnsSyncedOnly() async {
        let dataSource = LyricsDataSourceImpl(
            api: LRCLibStub(get: { _, _, _ in
                LyricsResult(trackName: "Song", artistName: "Artist", plainLyrics: nil, syncedLyrics: "[00:00.00]Line")
            })
        )

        let result = await dataSource.get(title: "Song", artist: "Artist", duration: nil)

        #expect(result?.syncedLyrics == "[00:00.00]Line")
        #expect(result?.plainLyrics == nil)
    }

    @Test("get returns nil when API throws")
    func getReturnsNilOnAPIError() async {
        let dataSource = LyricsDataSourceImpl(
            api: LRCLibStub(get: { _, _, _ in throw StubError() })
        )

        let result = await dataSource.get(title: "Song", artist: "Artist", duration: nil)

        #expect(result == nil)
    }

    @Test("get forwards arguments verbatim to the API")
    func getForwardsArguments() async {
        let captured = ArgumentRecorder<(String, String, Int?)>()
        let dataSource = LyricsDataSourceImpl(
            api: LRCLibStub(get: { trackName, artistName, duration in
                await captured.set((trackName, artistName, duration))
                return LyricsResult(plainLyrics: "x")
            })
        )

        _ = await dataSource.get(title: "Numb", artist: "Linkin Park", duration: 187)
        let value = await captured.value

        #expect(value?.0 == "Numb")
        #expect(value?.1 == "Linkin Park")
        #expect(value?.2 == 187)
    }

    @Test("get truncates fractional duration to integer seconds")
    func getTruncatesDuration() async {
        let captured = ArgumentRecorder<(String, String, Int?)>()
        let dataSource = LyricsDataSourceImpl(
            api: LRCLibStub(get: { trackName, artistName, duration in
                await captured.set((trackName, artistName, duration))
                return LyricsResult(plainLyrics: "x")
            })
        )

        _ = await dataSource.get(title: "T", artist: "A", duration: 225.7)
        let value = await captured.value

        // LRCLib expects integer-second durations; the DataSource layer truncates.
        #expect(value?.2 == 225)
    }

    @Test("search returns decoded results")
    func searchReturnsDecodedResults() async {
        let dataSource = LyricsDataSourceImpl(
            api: LRCLibStub(search: { _ in
                [
                    LyricsResult(trackName: "Song A", artistName: "Artist A", syncedLyrics: "[00:00.00]Line"),
                    LyricsResult(trackName: "Song B", artistName: "Artist B", plainLyrics: "Plain line"),
                ]
            })
        )

        let result = await dataSource.search(query: "song")

        #expect(result?.count == 2)
        #expect(result?.first?.trackName == "Song A")
        #expect(result?.last?.trackName == "Song B")
    }

    @Test("search returns nil when API throws")
    func searchReturnsNilOnAPIError() async {
        let dataSource = LyricsDataSourceImpl(
            api: LRCLibStub(search: { _ in throw StubError() })
        )

        let result = await dataSource.search(query: "song")

        #expect(result == nil)
    }

    @Test("search forwards query verbatim")
    func searchForwardsQuery() async {
        let captured = ArgumentRecorder<String>()
        let dataSource = LyricsDataSourceImpl(
            api: LRCLibStub(search: { q in
                await captured.set(q)
                return []
            })
        )

        _ = await dataSource.search(query: "AC/DC & Friends")
        let value = await captured.value

        #expect(value == "AC/DC & Friends")
    }

    @Test("search returns empty array on empty result")
    func searchReturnsEmptyArray() async {
        let dataSource = LyricsDataSourceImpl(
            api: LRCLibStub(search: { _ in [] })
        )

        let result = await dataSource.search(query: "no matches")

        #expect(result?.isEmpty == true)
    }
}

private actor ArgumentRecorder<Value: Sendable> {
    private(set) var value: Value?
    func set(_ value: Value) { self.value = value }
}
