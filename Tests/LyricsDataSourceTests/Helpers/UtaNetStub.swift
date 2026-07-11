import Foundation

@testable import LyricsDataSource

/// Manual mock of the `UtaNet` protocol for testing `UtaNetLyricsDataSourceImpl`
/// without exercising URL construction or networking.
struct UtaNetStub: UtaNet {
    let searchSongsResult: @Sendable (_ keyword: String) async throws -> String
    let lyricsPageResult: @Sendable (_ songID: Int) async throws -> String

    init(
        searchSongs: @escaping @Sendable (_ keyword: String) async throws -> String = { _ in "" },
        lyricsPage: @escaping @Sendable (_ songID: Int) async throws -> String = { _ in "" }
    ) {
        self.searchSongsResult = searchSongs
        self.lyricsPageResult = lyricsPage
    }

    func searchSongs(keyword: String) async throws -> String {
        try await searchSongsResult(keyword)
    }

    func lyricsPage(songID: Int) async throws -> String {
        try await lyricsPageResult(songID)
    }
}

/// Trimmed-down replicas of the real uta-net markup (classes and structure as
/// served on 2026-07-11) shared by the parser and data-source tests.
enum UtaNetFixtures {
    /// Search results with three songs: a same-titled cover listed before the
    /// original (real uta-net ordering), plus an entity-bearing title. Includes
    /// a thead row (no song link) and a decorative row that must be skipped.
    static let searchHTML = """
        <!doctype html><html lang="ja"><head><meta charset="UTF-8"><title>検索結果</title></head><body>
        <table class="table table-sm table-borderless songlist-table th-col-5" summary="曲一覧1">
        <thead class="sp-none"><tr class="border-bottom"><th>曲名</th><th>歌手名</th><th>作詞者名</th></tr></thead>
        <tbody class="songlist-table-body">
        <tr class="border-bottom"><td class="sp-w-100"><a href="/song/319082/" class="py-2"><span class="fw-bold songlist-title">夜に駆ける</span><span class="d-block d-lg-none utaidashi">岩佐美咲</span></a></td><td class="sp-none fw-bold"><a href="/artist/12586/">岩佐美咲</a></td><td class="sp-none"><a href="/lyricist/43927/">Ayase</a></td></tr>
        <tr class="border-bottom"><td class="sp-w-100"><a href="/song/284748/" class="py-2"><span class="fw-bold songlist-title">夜に駆ける</span><span class="d-block d-lg-none utaidashi">YOASOBI</span></a></td><td class="sp-none fw-bold"><a href="/artist/22653/">YOASOBI</a></td><td class="sp-none"><a href="/lyricist/43927/">Ayase</a></td></tr>
        <tr class="border-bottom"><td class="sp-w-100"><a href="/song/100001/" class="py-2"><span class="fw-bold songlist-title">Q&amp;A</span></a></td><td class="sp-none fw-bold"><a href="/artist/100/">ＹＯＡＳＯＢＩ</a></td><td class="sp-none"><a href="/arranger/0/"></a></td></tr>
        </tbody></table>
        </body></html>
        """

    /// Lyrics page: `<br>`-separated lines, a stanza break (double `<br>`),
    /// an HTML entity, and a decoy div that must not be picked up.
    static let songHTML = """
        <!doctype html><html lang="ja"><head><meta charset="UTF-8"><title>歌詞</title></head><body>
        <div id="other_area">decoy text</div>
        <div id="kashi_area" itemprop="text">沈むように溶けてゆくように<br />二人だけの空が広がる夜に<br /><br />「さよなら」&amp;その一言</div>
        </body></html>
        """

    static let expectedLyrics = """
        沈むように溶けてゆくように
        二人だけの空が広がる夜に

        「さよなら」&その一言
        """
}
