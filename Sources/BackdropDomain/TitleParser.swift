public struct TitleParser: Sendable {
    private static let noiseWords: Set<String> = [
        "mv", "pv", "official video", "official music video", "music video",
        "lyric video", "lyrics video", "the first take", "audio", "official audio",
        "full ver.", "full version", "short ver.", "short version", "topic", "vevo",
    ]

    private static let bracketPatterns = [
        "【[^】]*】", "「[^」]*」", "『[^』]*』",
        "\\([^)]*\\)", "（[^）]*）", "\\[[^\\]]*\\]",
    ]

    public init() {}

    public func stripBrackets(_ s: String) -> String {
        Self.bracketPatterns.reduce(s) { result, pattern in
            result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }.trimmingCharacters(in: .whitespaces)
    }

    public func isNoise(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        return Self.noiseWords.contains(trimmed.lowercased())
    }

    public func splitTitle(_ title: String) -> [String] {
        [" - ", " / ", " | ", "｜"]
            .reduce([title]) { parts, sep in parts.flatMap { $0.components(separatedBy: sep) } }
            .map { stripBrackets($0).trimmingCharacters(in: .whitespaces) }
            .filter { !isNoise($0) }
    }

    public func generateCandidates(title: String, artist: String) -> [SearchCandidate] {
        let parts = splitTitle(title)
        let cleaned = stripBrackets(title)
        let artistUsable = !isNoise(artist)

        let candidates: [SearchCandidate] = [
            artistUsable ? [SearchCandidate(title: cleaned, artist: artist)] : [],
            parts.count >= 2
                ? [SearchCandidate(title: parts[1], artist: parts[0]),
                   SearchCandidate(title: parts[0], artist: parts[1])]
                : [],
            artistUsable
                ? parts.filter { $0 != cleaned }.map { SearchCandidate(title: $0, artist: artist) }
                : [],
            parts.count == 1 && !artistUsable
                ? [SearchCandidate(title: parts[0], artist: "")]
                : [],
        ].flatMap { $0 }

        var seen = Set<String>()
        return candidates.filter { c in
            seen.insert("\(c.title.lowercased())|\(c.artist.lowercased())").inserted
        }
    }
}
