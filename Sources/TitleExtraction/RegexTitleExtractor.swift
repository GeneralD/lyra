import CollectionKit
import Domain

public struct RegexTitleExtractor {
    public init() {}
}

extension RegexTitleExtractor: Sendable {}

extension RegexTitleExtractor: TitleExtractor {
    public func extract(rawTitle: String, rawArtist: String) async -> [ResolvedTrack] {
        generateCandidates(title: rawTitle, artist: rawArtist)
    }
}

// MARK: - Noise patterns

/// Bracket-like patterns to strip entirely (noise brackets)
private let bracketPatterns = [
    "【[^】]*】",
    "\\([^)]*\\)", "（[^）]*）", "\\[[^\\]]*\\]",
]


/// Content-aware bracket patterns (case-insensitive) — strip brackets containing these
private let noiseBracketPatterns = [
    #"\(.*?(?:official|audio|video|lyrics|visualizer|music\s*video).*?\)"#,
    #"\(.*?(?:live|remaster(?:ed)?|acoustic|instrumental|piano\s*ver|full\s*ver|short\s*ver|cover).*?\)"#,
    #"\(.*?(?:\d{4}\s*remaster).*?\)"#,
    #"（.*?(?:official|live|remaster).*?）"#,
    #"\[.*?\]"#,
]

/// Suffix patterns after hyphen to strip (case-insensitive)
private let suffixPatterns = [
    #"\s*-\s*(?:official|audio|video|lyrics)\s*$"#,
    #"\s*-\s*(?:live|remaster(?:ed)?)\s*.*$"#,
    #"\s*-\s*\d{4}\s*remaster.*$"#,
]

/// Words that indicate a segment is noise
private let noiseWords: Set<String> = [
    "mv", "pv", "official video", "official music video", "music video",
    "lyric video", "lyrics video", "the first take", "audio", "official audio",
    "full ver.", "full version", "short ver.", "short version", "topic", "vevo",
    "hd", "4k", "visualizer", "official", "shorts",
]

/// Artist name suffixes to strip
private let artistSuffixPatterns = [
    #"\s*-\s*Topic$"#,
    #"\s*VEVO$"#,
    #"\s*Official\s*Channel$"#,
    #"\s*Official$"#,
]

// MARK: - Public API

extension RegexTitleExtractor {
    /// Normalize a title by removing noise brackets, suffixes, and series markers
    public func normalize(_ title: String) -> String {
        var s = title

        // Remove everything after / (channel/series name like "THE FIRST TAKE")
        if let slashRange = s.range(of: " / ") {
            s = String(s[..<slashRange.lowerBound])
        }

        // Remove content-aware noise brackets
        for pattern in noiseBracketPatterns {
            s = s.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }

        // Remove noise suffixes after hyphen
        for pattern in suffixPatterns {
            s = s.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }

        // Collapse whitespace
        return s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Normalize an artist name by removing platform suffixes
    public func normalizeArtist(_ artist: String) -> String {
        artistSuffixPatterns.reduce(artist) {
            $0.replacingOccurrences(of: $1, with: "", options: [.regularExpression, .caseInsensitive])
        }
        .trimmingCharacters(in: .whitespaces)
    }

    /// Strip all bracket content (aggressive — for fallback searches)
    public func stripBrackets(_ s: String) -> String {
        bracketPatterns
            .reduce(s) { $0.replacingOccurrences(of: $1, with: "", options: .regularExpression) }
            .trimmingCharacters(in: .whitespaces)
    }

    /// Parse artist and title from common formats:
    /// - `Artist「Title」-suffix-`
    /// - `Artist『Title』`
    /// - `Artist - Title (noise)`
    public func parseArtistTitle(_ raw: String) -> (artist: String?, title: String) {
        let normalized = normalize(raw)

        // Try Japanese quote brackets: Artist「Title」
        if let match = normalized.firstMatch(of: /「([^」]+)」|『([^』]+)』/) {
            let title = (match.output.1 ?? match.output.2)
                .map(String.init) ?? normalized
            let artist = normalized[..<match.range.lowerBound]
                .trimmingCharacters(in: .whitespaces)
            return (artist.isEmpty ? nil : artist, title)
        }

        // Try "Artist - Title"
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
            .unless(isNoise)
    }

    public func generateCandidates(title: String, artist: String) -> [ResolvedTrack] {
        let normalizedArtist = normalizeArtist(artist)
        let parsed = parseArtistTitle(title)
        let normalized = normalize(title)
        let stripped = stripBrackets(title)
        let parts = splitTitle(title)
        let artistUsable = !isNoise(normalizedArtist)

        var seen = Set<String>()
        return [
            // From parseArtistTitle (best for "Artist - Title" format)
            parsed.artist.map { [ResolvedTrack(title: parsed.title, artist: $0)] } ?? [],
            // Normalized title with MediaRemote artist
            artistUsable ? [ResolvedTrack(title: normalized, artist: normalizedArtist)] : [],
            // Stripped title with artist
            artistUsable ? [ResolvedTrack(title: stripped, artist: normalizedArtist)] : [],
            // Split parts as artist-title pairs
            parts.count >= 2
                ? [ResolvedTrack(title: parts[1], artist: parts[0]),
                   ResolvedTrack(title: parts[0], artist: parts[1])]
                : [],
            // Individual parts with artist
            artistUsable
                ? parts.unless { $0 == stripped }.map { ResolvedTrack(title: $0, artist: normalizedArtist) }
                : [],
            // Title only (last resort)
            parts.count == 1 && !artistUsable
                ? [ResolvedTrack(title: parts[0], artist: "")]
                : [],
        ]
        .flatten
        .filter { seen.insert("\($0.title.lowercased())|\($0.artist.lowercased())").inserted }
    }
}
