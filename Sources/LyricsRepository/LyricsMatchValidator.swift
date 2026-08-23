import Domain

struct LyricsMatchValidator {
    let titleSimilarityThreshold: Double
    let durationToleranceSeconds: Double
    let exactTitleDurationToleranceRatio: Double
    let exactTitleDurationToleranceFloor: Double

    init(
        titleSimilarityThreshold: Double = 0.6,
        durationToleranceSeconds: Double = 5,
        exactTitleDurationToleranceRatio: Double = 0.3,
        exactTitleDurationToleranceFloor: Double = 20
    ) {
        self.titleSimilarityThreshold = titleSimilarityThreshold
        self.durationToleranceSeconds = durationToleranceSeconds
        self.exactTitleDurationToleranceRatio = exactTitleDurationToleranceRatio
        self.exactTitleDurationToleranceFloor = exactTitleDurationToleranceFloor
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
        guard let candidateDuration = Self.knownDuration(candidate.duration),
            let resultDuration = Self.knownDuration(result.duration)
        else { return nil }
        return abs(candidateDuration - resultDuration)
    }
}

extension LyricsMatchValidator {
    private func titleMatches(candidate: Track, result: LyricsResult) -> Bool {
        guard let resultTitle = result.trackName, !resultTitle.isEmpty else { return true }
        if titleMatchesExactly(candidate: candidate, result: result) { return true }
        return Self.similarity(Self.normalized(candidate.title), Self.normalized(resultTitle)) >= titleSimilarityThreshold
    }

    // Strong title evidence: the two titles carry the same words, or the catalog's title
    // is the played one plus trailing version tokens. Famous-song catalogs append
    // remaster/live/version suffixes ("Yesterday - Remastered 2009"), so the whole-token
    // prefix — matched on word boundaries, so "Yes" never matches "Yesterday" — is the
    // same song, which the plain concatenated-similarity metric alone would reject (#326).
    // Unlike `titleMatches`, a missing result title is *absent* evidence, not a pass.
    private func titleMatchesExactly(candidate: Track, result: LyricsResult) -> Bool {
        guard let resultTitle = result.trackName, !resultTitle.isEmpty else { return false }
        return Self.normalized(candidate.title) == Self.normalized(resultTitle)
            || Self.isTokenPrefix(Self.tokens(candidate.title), Self.tokens(resultTitle))
    }

    private func durationMatches(candidate: Track, result: LyricsResult) -> Bool {
        guard let delta = durationDelta(candidate: candidate, result: result),
            let catalogDuration = Self.knownDuration(result.duration)
        else { return true }
        return delta <= durationTolerance(candidate: candidate, result: result, catalogDuration: catalogDuration)
    }

    // Duration is a discriminator whose strictness should scale inversely with how sure
    // we are of the title. On an exact title it is only a sanity check — the same song
    // legitimately ships at different lengths (TV size, album vs single cut, fade-out
    // differences), and the flat ±5s gate rejected ~30 logged matches that were correct,
    // then re-rejected them out of the cache on every replay (#326). A merely-fuzzy title
    // leaves duration as the only evidence, so it keeps the strict tolerance.
    //
    // The catalog's duration sets the scale, never the played track's: a media source that
    // misreports a length (a whole stream read as one 1975s "track") would otherwise buy
    // itself a proportionally huge tolerance and validate anything.
    private func durationTolerance(candidate: Track, result: LyricsResult, catalogDuration: Double) -> Double {
        guard titleMatchesExactly(candidate: candidate, result: result) else { return durationToleranceSeconds }
        return max(exactTitleDurationToleranceFloor, catalogDuration * exactTitleDurationToleranceRatio)
    }

    // A media source that cannot read a length reports 0 (or a negative), which is
    // "unknown" rather than a zero-second track. Comparing it as a real length rejected
    // every catalog entry for that play (#326).
    private static func knownDuration(_ duration: Double?) -> Double? {
        guard let duration, duration > 0 else { return nil }
        return duration
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
