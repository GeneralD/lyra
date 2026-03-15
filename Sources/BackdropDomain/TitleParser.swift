import CollectionKit

public struct TitleParser {
    public init() {}
}

extension TitleParser: Sendable {}

private let noiseWords: Set<String> = [
    "mv", "pv", "official video", "official music video", "music video",
    "lyric video", "lyrics video", "the first take", "audio", "official audio",
    "full ver.", "full version", "short ver.", "short version", "topic", "vevo",
]

private let bracketPatterns = [
    "【[^】]*】", "「[^」]*」", "『[^』]*』",
    "\\([^)]*\\)", "（[^）]*）", "\\[[^\\]]*\\]",
]

extension TitleParser {
    public func stripBrackets(_ s: String) -> String {
        bracketPatterns
            .reduce(s) { $0.replacingOccurrences(of: $1, with: "", options: .regularExpression) }
            .trimmingCharacters(in: .whitespaces)
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

    public func generateCandidates(title: String, artist: String) -> [SearchCandidate] {
        let parts = splitTitle(title)
        let cleaned = stripBrackets(title)
        let artistUsable = !isNoise(artist)

        var seen = Set<String>()
        return [
            artistUsable ? [SearchCandidate(title: cleaned, artist: artist)] : [],
            parts.count >= 2
                ? [SearchCandidate(title: parts[1], artist: parts[0]),
                   SearchCandidate(title: parts[0], artist: parts[1])]
                : [],
            artistUsable
                ? parts.unless { $0 == cleaned }.map { SearchCandidate(title: $0, artist: artist) }
                : [],
            parts.count == 1 && !artistUsable
                ? [SearchCandidate(title: parts[0], artist: "")]
                : [],
        ]
        .flatten
        .filter { seen.insert("\($0.title.lowercased())|\($0.artist.lowercased())").inserted }
    }
}
