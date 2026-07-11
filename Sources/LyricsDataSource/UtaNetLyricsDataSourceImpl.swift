import Domain
import Foundation

public struct UtaNetLyricsDataSourceImpl: Sendable {
    private let api: any UtaNet

    public init() {
        self.init(api: UtaNetAPI())
    }

    init(api: any UtaNet) {
        self.api = api
    }
}

extension UtaNetLyricsDataSourceImpl: LyricsDataSource {
    public func get(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? {
        let titleKey = Self.matchKey(title)
        let artistKey = Self.matchKey(artist)
        // Same-titled different songs are common on uta-net (covers are listed
        // under the covering artist, and unrelated songs share titles too), so
        // a lookup with no artist to discriminate on is not answerable safely.
        guard !titleKey.isEmpty, !artistKey.isEmpty else { return nil }

        let keyword = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let html = try? await api.searchSongs(keyword: keyword) else { return nil }
        let rows = UtaNetHTMLParser.songRows(inSearchResults: html)
        guard
            let match = rows.first(where: { row in
                Self.matchKey(row.title) == titleKey && Self.matchKey(row.artist) == artistKey
            })
        else { return nil }
        return await lyricsResult(for: match)
    }

    public func search(query: String) async -> [LyricsResult]? {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let html = try? await api.searchSongs(keyword: keyword) else { return nil }
        let rows = UtaNetHTMLParser.songRows(inSearchResults: html)
        // Every returned result costs one extra page fetch for its lyrics body,
        // so only the top-relevance row is materialized, not the whole list.
        guard let top = rows.first else { return [] }
        guard let result = await lyricsResult(for: top) else { return [] }
        return [result]
    }
}

extension UtaNetLyricsDataSourceImpl {
    private func lyricsResult(for row: UtaNetHTMLParser.SongRow) async -> LyricsResult? {
        guard let page = try? await api.lyricsPage(songID: row.songID),
            let lyrics = UtaNetHTMLParser.lyrics(inSongPage: page)
        else { return nil }
        // id stays nil: positive ids are LRCLIB's namespace in the lyrics cache
        // (id-less results get a negative synthetic id there), and duration stays
        // nil so LyricsMatchValidator skips its duration check instead of failing.
        return LyricsResult(trackName: row.title, artistName: row.artist, plainLyrics: lyrics)
    }

    /// Comparison key that is case-, width-, and diacritic-insensitive and
    /// keeps only letters and numbers — uta-net listings freely mix full- and
    /// half-width forms and decorative punctuation around otherwise-equal names.
    private static func matchKey(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }
}
