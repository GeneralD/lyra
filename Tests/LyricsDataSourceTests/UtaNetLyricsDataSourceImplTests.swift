import Domain
import Foundation
import Testing

@testable import LyricsDataSource

@Suite("UtaNetLyricsDataSourceImpl")
struct UtaNetLyricsDataSourceImplTests {
    @Test("default init() wires the URLSession-backed UtaNetAPI")
    func defaultInitInstantiates() {
        // Just exercising init() to cover the production wiring.
        // We don't make a network call — only verify construction succeeds.
        _ = UtaNetLyricsDataSourceImpl()
    }

    @Test("get returns plain lyrics when title and artist match a row")
    func getReturnsLyricsOnMatch() async {
        let dataSource = UtaNetLyricsDataSourceImpl(
            api: UtaNetStub(
                searchSongs: { _ in UtaNetFixtures.searchHTML },
                lyricsPage: { _ in UtaNetFixtures.songHTML }
            )
        )

        let result = await dataSource.get(title: "夜に駆ける", artist: "YOASOBI", duration: nil)

        #expect(result?.trackName == "夜に駆ける")
        #expect(result?.artistName == "YOASOBI")
        #expect(result?.plainLyrics == UtaNetFixtures.expectedLyrics)
        #expect(result?.syncedLyrics == nil)
    }

    @Test("get skips a same-titled cover and fetches the artist-matching row's page")
    func getSkipsCoverRow() async {
        let requestedID = ArgumentRecorder<Int>()
        let dataSource = UtaNetLyricsDataSourceImpl(
            api: UtaNetStub(
                searchSongs: { _ in UtaNetFixtures.searchHTML },
                lyricsPage: { songID in
                    await requestedID.set(songID)
                    return UtaNetFixtures.songHTML
                }
            )
        )

        _ = await dataSource.get(title: "夜に駆ける", artist: "YOASOBI", duration: nil)

        // The cover (岩佐美咲, /song/319082/) comes first in the fixture; the
        // artist filter must pick YOASOBI's /song/284748/ instead.
        #expect(await requestedID.value == 284_748)
    }

    @Test("get matches artist width- and case-insensitively")
    func getMatchesWidthInsensitively() async {
        let dataSource = UtaNetLyricsDataSourceImpl(
            api: UtaNetStub(
                searchSongs: { _ in UtaNetFixtures.searchHTML },
                lyricsPage: { _ in UtaNetFixtures.songHTML }
            )
        )

        // Fixture row: title "Q&A" / artist "ＹＯＡＳＯＢＩ" (full-width).
        let result = await dataSource.get(title: "q&a", artist: "yoasobi", duration: nil)

        #expect(result?.trackName == "Q&A")
    }

    @Test("get leaves id and duration nil — uta-net has neither an LRCLIB id nor a track duration")
    func getLeavesIDAndDurationNil() async {
        let dataSource = UtaNetLyricsDataSourceImpl(
            api: UtaNetStub(
                searchSongs: { _ in UtaNetFixtures.searchHTML },
                lyricsPage: { _ in UtaNetFixtures.songHTML }
            )
        )

        let result = await dataSource.get(title: "夜に駆ける", artist: "YOASOBI", duration: 258)

        #expect(result?.id == nil)
        #expect(result?.duration == nil)
    }

    @Test("get returns nil when artist is empty — same-titled songs are indistinguishable")
    func getRequiresArtist() async {
        let dataSource = UtaNetLyricsDataSourceImpl(
            api: UtaNetStub(searchSongs: { _ in UtaNetFixtures.searchHTML })
        )

        let result = await dataSource.get(title: "夜に駆ける", artist: "", duration: nil)

        #expect(result == nil)
    }

    @Test("get returns nil when no row matches the artist")
    func getReturnsNilWithoutArtistMatch() async {
        let dataSource = UtaNetLyricsDataSourceImpl(
            api: UtaNetStub(searchSongs: { _ in UtaNetFixtures.searchHTML })
        )

        let result = await dataSource.get(title: "夜に駆ける", artist: "Somebody Else", duration: nil)

        #expect(result == nil)
    }

    @Test("get returns nil when the search request throws")
    func getReturnsNilOnSearchError() async {
        let dataSource = UtaNetLyricsDataSourceImpl(
            api: UtaNetStub(searchSongs: { _ in throw StubError() })
        )

        let result = await dataSource.get(title: "夜に駆ける", artist: "YOASOBI", duration: nil)

        #expect(result == nil)
    }

    @Test("get returns nil when the lyrics page request throws")
    func getReturnsNilOnLyricsPageError() async {
        let dataSource = UtaNetLyricsDataSourceImpl(
            api: UtaNetStub(
                searchSongs: { _ in UtaNetFixtures.searchHTML },
                lyricsPage: { _ in throw StubError() }
            )
        )

        let result = await dataSource.get(title: "夜に駆ける", artist: "YOASOBI", duration: nil)

        #expect(result == nil)
    }

    @Test("get returns nil when the lyrics page has no lyrics body")
    func getReturnsNilWithoutLyricsBody() async {
        let dataSource = UtaNetLyricsDataSourceImpl(
            api: UtaNetStub(
                searchSongs: { _ in UtaNetFixtures.searchHTML },
                lyricsPage: { _ in "<html><body>instrumental</body></html>" }
            )
        )

        let result = await dataSource.get(title: "夜に駆ける", artist: "YOASOBI", duration: nil)

        #expect(result == nil)
    }

    @Test("search materializes only the top row")
    func searchReturnsTopRowOnly() async {
        let dataSource = UtaNetLyricsDataSourceImpl(
            api: UtaNetStub(
                searchSongs: { _ in UtaNetFixtures.searchHTML },
                lyricsPage: { _ in UtaNetFixtures.songHTML }
            )
        )

        let results = await dataSource.search(query: "夜に駆ける")

        #expect(results?.count == 1)
        #expect(results?.first?.artistName == "岩佐美咲")
        #expect(results?.first?.plainLyrics == UtaNetFixtures.expectedLyrics)
    }

    @Test("search returns empty array when nothing matches")
    func searchReturnsEmptyArray() async {
        let dataSource = UtaNetLyricsDataSourceImpl(
            api: UtaNetStub(searchSongs: { _ in "<html><body>0件</body></html>" })
        )

        let results = await dataSource.search(query: "no matches")

        #expect(results?.isEmpty == true)
    }

    @Test("search returns nil when the request throws")
    func searchReturnsNilOnError() async {
        let dataSource = UtaNetLyricsDataSourceImpl(
            api: UtaNetStub(searchSongs: { _ in throw StubError() })
        )

        let results = await dataSource.search(query: "夜に駆ける")

        #expect(results == nil)
    }

    @Test("get forwards the trimmed title as the search keyword")
    func getForwardsTrimmedKeyword() async {
        let keyword = ArgumentRecorder<String>()
        let dataSource = UtaNetLyricsDataSourceImpl(
            api: UtaNetStub(searchSongs: { kw in
                await keyword.set(kw)
                return ""
            })
        )

        _ = await dataSource.get(title: "  夜に駆ける \n", artist: "YOASOBI", duration: nil)

        #expect(await keyword.value == "夜に駆ける")
    }
}

private actor ArgumentRecorder<Value: Sendable> {
    private(set) var value: Value?
    func set(_ value: Value) { self.value = value }
}
