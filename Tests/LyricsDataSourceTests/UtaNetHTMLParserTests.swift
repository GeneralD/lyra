import Foundation
import Testing

@testable import LyricsDataSource

@Suite("UtaNetHTMLParser")
struct UtaNetHTMLParserTests {
    @Test("search results yield one row per song link, header rows drop out")
    func songRowsParsed() {
        let rows = UtaNetHTMLParser.songRows(inSearchResults: UtaNetFixtures.searchHTML)

        #expect(rows.count == 3)
        #expect(rows[0] == .init(songID: 319_082, title: "夜に駆ける", artist: "岩佐美咲"))
        #expect(rows[1] == .init(songID: 284_748, title: "夜に駆ける", artist: "YOASOBI"))
    }

    @Test("HTML entities in titles are decoded")
    func entitiesDecoded() {
        let rows = UtaNetHTMLParser.songRows(inSearchResults: UtaNetFixtures.searchHTML)

        #expect(rows.last?.title == "Q&A")
    }

    @Test("artist comes from the artist link, not the lyricist or arranger links")
    func artistFromArtistLink() {
        let rows = UtaNetHTMLParser.songRows(inSearchResults: UtaNetFixtures.searchHTML)

        #expect(rows[0].artist == "岩佐美咲")
        #expect(rows.allSatisfy { $0.artist != "Ayase" })
    }

    @Test("page without a songlist table yields no rows")
    func noTableNoRows() {
        let rows = UtaNetHTMLParser.songRows(inSearchResults: "<html><body><p>no results</p></body></html>")

        #expect(rows.isEmpty)
    }

    @Test("duplicate song ids collapse to the first occurrence")
    func duplicateRowsDeduplicated() {
        let html = """
            <table class="songlist-table"><tbody>
            <tr><td><a href="/song/1/"><span class="songlist-title">A</span></a></td><td><a href="/artist/1/">X</a></td></tr>
            <tr><td><a href="/song/1/"><span class="songlist-title">A</span></a></td><td><a href="/artist/1/">X</a></td></tr>
            </tbody></table>
            """

        let rows = UtaNetHTMLParser.songRows(inSearchResults: html)

        #expect(rows.count == 1)
    }

    @Test("lyrics lines are split on <br>, stanza breaks survive as blank lines")
    func lyricsParsed() {
        let lyrics = UtaNetHTMLParser.lyrics(inSongPage: UtaNetFixtures.songHTML)

        #expect(lyrics == UtaNetFixtures.expectedLyrics)
    }

    @Test("page without a kashi_area div yields nil")
    func missingLyricsAreaIsNil() {
        let lyrics = UtaNetHTMLParser.lyrics(inSongPage: "<html><body><div id=\"other\">x</div></body></html>")

        #expect(lyrics == nil)
    }

    @Test("empty kashi_area yields nil, not an empty string")
    func emptyLyricsAreaIsNil() {
        let lyrics = UtaNetHTMLParser.lyrics(inSongPage: "<div id=\"kashi_area\"> <br /> </div>")

        #expect(lyrics == nil)
    }

    @Test("text nested in inline elements inside kashi_area is preserved")
    func nestedInlineTextPreserved() {
        let lyrics = UtaNetHTMLParser.lyrics(inSongPage: "<div id=\"kashi_area\">前<span>中</span>後<br />次行</div>")

        #expect(lyrics == "前中後\n次行")
    }
}
