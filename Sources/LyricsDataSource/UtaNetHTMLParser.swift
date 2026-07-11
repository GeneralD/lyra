import Foundation

/// Extracts structured data from uta-net.com pages with Foundation's
/// `XMLDocument` HTML-tidy mode (libxml2) — deliberately no third-party HTML
/// parser: the two extractions below (one table, one div) don't justify a new
/// dependency, and the tidy parser copes with the site's minified markup.
enum UtaNetHTMLParser {
    struct SongRow: Equatable {
        let songID: Int
        let title: String
        let artist: String
    }

    /// Search-result rows: every `<tr>` of the songlist table that carries a
    /// `/song/<id>/` link yields one row; header rows have no link and drop out.
    static func songRows(inSearchResults html: String) -> [SongRow] {
        guard let document = tidiedDocument(html),
            let rows = try? document.nodes(forXPath: "//table[contains(@class,'songlist-table')]//tr")
        else { return [] }
        var seenIDs = Set<Int>()
        return rows.compactMap(songRow(from:)).filter { seenIDs.insert($0.songID).inserted }
    }

    /// Lyrics text of a song page: `#kashi_area` holds plain text separated by
    /// `<br>` elements; stanza breaks are two consecutive `<br>`s and survive
    /// as blank lines.
    static func lyrics(inSongPage html: String) -> String? {
        guard let document = tidiedDocument(html),
            let area = (try? document.nodes(forXPath: "//div[@id='kashi_area']"))?.first
        else { return nil }
        var lines: [String] = []
        var current = ""
        collectText(area, lines: &lines, current: &current)
        lines.append(current)
        let text = lines.joined(separator: "\n")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

extension UtaNetHTMLParser {
    private static func tidiedDocument(_ html: String) -> XMLDocument? {
        // libxml2's HTML parser does not sniff the HTML5 `<meta charset>` form
        // and would fall back to Latin-1, garbling the Japanese text. A UTF-8
        // BOM forces the encoding regardless of what the page declares.
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(contentsOf: html.utf8)
        return try? XMLDocument(data: data, options: [.documentTidyHTML])
    }

    private static func songRow(from row: XMLNode) -> SongRow? {
        guard
            let href = firstNode(in: row, xPath: ".//a[starts-with(@href,'/song/')]/@href")?.stringValue,
            let songID = songID(fromHref: href),
            let title = firstNode(in: row, xPath: ".//span[contains(@class,'songlist-title')]")?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !title.isEmpty,
            let artist = firstNode(in: row, xPath: ".//a[starts-with(@href,'/artist/')]")?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !artist.isEmpty
        else { return nil }
        return SongRow(songID: songID, title: title, artist: artist)
    }

    private static func firstNode(in node: XMLNode, xPath: String) -> XMLNode? {
        (try? node.nodes(forXPath: xPath))?.first
    }

    private static func songID(fromHref href: String) -> Int? {
        guard let range = href.range(of: "/song/") else { return nil }
        let digits = href[range.upperBound...].prefix(while: \.isNumber)
        return digits.isEmpty ? nil : Int(digits)
    }

    private static func collectText(_ node: XMLNode, lines: inout [String], current: inout String) {
        if let element = node as? XMLElement, element.name?.lowercased() == "br" {
            lines.append(current)
            current = ""
            return
        }
        if node.kind == .text {
            current += node.stringValue ?? ""
        }
        for child in node.children ?? [] {
            collectText(child, lines: &lines, current: &current)
        }
    }
}
