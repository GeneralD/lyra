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
}

extension LyricsMatchValidator {
    private func titleMatches(candidate: Track, result: LyricsResult) -> Bool {
        guard let resultTitle = result.trackName, !resultTitle.isEmpty else { return true }
        return Self.similarity(Self.normalized(candidate.title), Self.normalized(resultTitle)) >= titleSimilarityThreshold
    }

    private func durationMatches(candidate: Track, result: LyricsResult) -> Bool {
        guard let candidateDuration = candidate.duration, let resultDuration = result.duration else { return true }
        return abs(candidateDuration - resultDuration) <= durationToleranceSeconds
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
