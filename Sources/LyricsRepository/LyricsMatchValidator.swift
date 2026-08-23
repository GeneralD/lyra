import Domain

struct LyricsMatchValidator {
    let titleSimilarityThreshold: Double
    let durationToleranceSeconds: Double

    init(titleSimilarityThreshold: Double = 0.6, durationToleranceSeconds: Double = 5) {
        self.titleSimilarityThreshold = titleSimilarityThreshold
        self.durationToleranceSeconds = durationToleranceSeconds
    }

    func isValid(candidate: Track, result: LyricsResult) -> Bool {
        titleMatches(candidate: candidate, result: result) && durationMatches(candidate: candidate, result: result)
    }

    // Reason accessors for the resolution debug log (#331) — expose *why* a candidate
    // matched or not, not just the boolean. `nil` means the corresponding check does
    // not apply (empty result title, or a missing duration on either side), matching
    // `isValid`'s skip semantics.
    func titleSimilarity(candidate: Track, result: LyricsResult) -> Double? {
        guard let resultTitle = result.trackName, !resultTitle.isEmpty else { return nil }
        return Self.similarity(Self.normalized(candidate.title), Self.normalized(resultTitle))
    }

    func durationDelta(candidate: Track, result: LyricsResult) -> Double? {
        guard let candidateDuration = candidate.duration, let resultDuration = result.duration else { return nil }
        return abs(candidateDuration - resultDuration)
    }
}

extension LyricsMatchValidator {
    private func titleMatches(candidate: Track, result: LyricsResult) -> Bool {
        guard let resultTitle = result.trackName, !resultTitle.isEmpty else { return true }
        // Famous-song catalogs append remaster/live/version suffixes ("Yesterday -
        // Remastered 2009"), so LRCLIB's canonical title is the played title plus extra
        // trailing tokens. Accept a whole-token prefix match first — matched on word
        // boundaries so "Yes" never matches "Yesterday" — before the fuzzy fallback,
        // which the plain concatenated-similarity metric alone would reject (#326).
        if Self.isTokenPrefix(Self.tokens(candidate.title), Self.tokens(resultTitle)) { return true }
        return Self.similarity(Self.normalized(candidate.title), Self.normalized(resultTitle)) >= titleSimilarityThreshold
    }

    private func durationMatches(candidate: Track, result: LyricsResult) -> Bool {
        guard let candidateDuration = candidate.duration, let resultDuration = result.duration else { return true }
        return abs(candidateDuration - resultDuration) <= durationToleranceSeconds
    }

    private static func tokens(_ text: String) -> [String] {
        text.lowercased().split { !($0.isLetter || $0.isNumber) }.map(String.init)
    }

    // One token list is a whole-token prefix of the other (in either direction).
    private static func isTokenPrefix(_ a: [String], _ b: [String]) -> Bool {
        let (shorter, longer) = a.count <= b.count ? (a, b) : (b, a)
        guard !shorter.isEmpty else { return false }
        return Array(longer.prefix(shorter.count)) == shorter
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func similarity(_ a: String, _ b: String) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 1 }
        let maxLength = max(a.count, b.count)
        guard maxLength > 0 else { return 1 }
        let distance = levenshteinDistance(Array(a), Array(b))
        return 1 - Double(distance) / Double(maxLength)
    }

    private static func levenshteinDistance(_ a: [Character], _ b: [Character]) -> Int {
        var previous = Array(0...b.count)
        for (i, charA) in a.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: b.count)
            for (j, charB) in b.enumerated() {
                current[j + 1] = charA == charB ? previous[j] : 1 + min(previous[j], previous[j + 1], current[j])
            }
            previous = current
        }
        return previous[b.count]
    }
}
