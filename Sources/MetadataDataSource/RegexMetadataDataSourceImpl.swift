import Domain

public struct RegexMetadataDataSourceImpl {
    public init() {}
}

extension RegexMetadataDataSourceImpl: Sendable {}

extension RegexMetadataDataSourceImpl: MetadataDataSource {
    public func resolve(track: Track) async -> [Track] {
        generateCandidates(title: track.title, artist: track.artist)
    }
}

// MARK: - Noise patterns

private let bracketPatterns = [
    "【[^】]*】",
    "\\([^)]*\\)", "（[^）]*）", "\\[[^\\]]*\\]",
]

private let noiseBracketPatterns = [
    #"\(.*?(?:official|audio|video|lyrics|visualizer|music\s*video).*?\)"#,
    #"\(.*?(?:live|remaster(?:ed)?|acoustic|instrumental|piano\s*ver|full\s*ver|short\s*ver|cover).*?\)"#,
    #"\(.*?(?:\d{4}\s*remaster).*?\)"#,
    #"（.*?(?:official|live|remaster).*?）"#,
    #"\[.*?\]"#,
]

private let suffixPatterns = [
    #"\s*-\s*(?:official|audio|video|lyrics)\s*$"#,
    #"\s*-\s*(?:live|remaster(?:ed)?)\s*.*$"#,
    #"\s*-\s*\d{4}\s*remaster.*$"#,
]

private let noiseWords: Set<String> = [
    "mv", "pv", "official video", "official music video", "music video",
    "lyric video", "lyrics video", "the first take", "audio", "official audio",
    "full ver.", "full version", "short ver.", "short version", "topic", "vevo",
    "hd", "4k", "visualizer", "official", "shorts",
]

private let artistSuffixPatterns = [
    #"\s*-\s*Topic$"#,
    #"\s*VEVO$"#,
    #"\s*Official\s*Channel$"#,
    #"\s*Official$"#,
]

// MARK: - Public API

extension RegexMetadataDataSourceImpl {
    public func normalize(_ title: String) -> String {
        var s = title

        if let slashRange = s.range(of: " / ") {
            s = String(s[..<slashRange.lowerBound])
        }

        for pattern in noiseBracketPatterns {
            s = s.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }

        for pattern in suffixPatterns {
            s = s.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }

        return s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    public func normalizeArtist(_ artist: String) -> String {
        artistSuffixPatterns.reduce(artist) {
            $0.replacingOccurrences(of: $1, with: "", options: [.regularExpression, .caseInsensitive])
        }
        .trimmingCharacters(in: .whitespaces)
    }

    public func stripBrackets(_ s: String) -> String {
        bracketPatterns
            .reduce(s) { $0.replacingOccurrences(of: $1, with: "", options: .regularExpression) }
            .trimmingCharacters(in: .whitespaces)
    }

    public func parseArtistTitle(_ raw: String) -> (artist: String?, title: String) {
        let normalized = normalize(raw)

        if let match = normalized.firstMatch(of: /「([^」]+)」|『([^』]+)』/) {
            // Regex alternation guarantees one capture is non-nil on match.
            let title = String(match.output.1 ?? match.output.2!)
            let artist = normalized[..<match.range.lowerBound]
                .trimmingCharacters(in: .whitespaces)
            return (artist.isEmpty ? nil : artist, title)
        }

        guard let dashRange = normalized.range(of: " - ") else {
            return (nil, normalized)
        }
        let artist = String(normalized[..<dashRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        let title = String(normalized[dashRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        return (artist, title)
    }

    public func isNoise(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        return noiseWords.contains(trimmed.lowercased())
    }

    public func splitTitle(_ title: String) -> [String] {
        [" - ", " / ", " | ", "｜"]
            .reduce([title]) { parts, sep in parts.flatMap { $0.components(separatedBy: sep) } }
            .map { stripBrackets($0).trimmingCharacters(in: .whitespaces) }
            .filter { !isNoise($0) }
    }

    public func generateCandidates(title: String, artist: String) -> [Track] {
        let normalizedArtist = normalizeArtist(artist)
        let parsed = parseArtistTitle(title)
        let normalized = normalize(title)
        let stripped = stripBrackets(title)
        let parts = splitTitle(title)
        let artistUsable = !isNoise(normalizedArtist)

        var seen = Set<String>()
        return [
            parsed.artist.map { [Track(title: parsed.title, artist: $0)] } ?? [],
            artistUsable ? [Track(title: normalized, artist: normalizedArtist)] : [],
            artistUsable ? [Track(title: stripped, artist: normalizedArtist)] : [],
            parts.count >= 2
                ? [
                    Track(title: parts[1], artist: parts[0]),
                    Track(title: parts[0], artist: parts[1]),
                ]
                : [],
            artistUsable
                ? parts.filter { $0 != stripped }.map { Track(title: $0, artist: normalizedArtist) }
                : [],
            parts.count == 1 && !artistUsable
                ? [Track(title: parts[0], artist: "")]
                : [],
        ]
        .flatMap { $0 }
        .filter { seen.insert("\($0.title.lowercased())|\($0.artist.lowercased())").inserted }
    }
}
