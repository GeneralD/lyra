import Domain
import Testing

@testable import LyricsRepository

@Suite("LyricsMatchValidator")
struct LyricsMatchValidatorTests {
    let validator = LyricsMatchValidator()

    @Test("exact title and duration match is valid")
    func exactMatch() {
        let candidate = Track(title: "Shape of You", artist: "Ed Sheeran", duration: 233)
        let result = LyricsResult(trackName: "Shape of You", artistName: "Ed Sheeran", duration: 233, plainLyrics: "lyrics")
        #expect(validator.isValid(candidate: candidate, result: result))
    }

    @Test("wildly different title is invalid")
    func differentTitleInvalid() {
        let candidate = Track(title: "Shape of You", artist: "Ed Sheeran", duration: 233)
        let result = LyricsResult(trackName: "Bohemian Rhapsody", artistName: "Queen", duration: 233, plainLyrics: "lyrics")
        #expect(!validator.isValid(candidate: candidate, result: result))
    }

    @Test("duration far outside tolerance is invalid even when title matches")
    func durationMismatchInvalid() {
        let candidate = Track(title: "Shape of You", artist: "Ed Sheeran", duration: 233)
        let result = LyricsResult(trackName: "Shape of You", artistName: "Ed Sheeran", duration: 400, plainLyrics: "lyrics")
        #expect(!validator.isValid(candidate: candidate, result: result))
    }

    @Test("duration within tolerance is valid")
    func durationWithinToleranceValid() {
        let candidate = Track(title: "Shape of You", artist: "Ed Sheeran", duration: 233)
        let result = LyricsResult(trackName: "Shape of You", artistName: "Ed Sheeran", duration: 236, plainLyrics: "lyrics")
        #expect(validator.isValid(candidate: candidate, result: result))
    }

    @Test("missing trackName on result skips title check")
    func missingTrackNameSkipsTitleCheck() {
        let candidate = Track(title: "Shape of You", artist: "Ed Sheeran", duration: 233)
        let result = LyricsResult(duration: 233, plainLyrics: "lyrics")
        #expect(validator.isValid(candidate: candidate, result: result))
    }

    @Test("missing duration on either side skips duration check")
    func missingDurationSkipsDurationCheck() {
        let candidate = Track(title: "Shape of You", artist: "Ed Sheeran")
        let result = LyricsResult(trackName: "Shape of You", artistName: "Ed Sheeran", plainLyrics: "lyrics")
        #expect(validator.isValid(candidate: candidate, result: result))
    }

    @Test("case and punctuation differences do not affect title match")
    func caseAndPunctuationIgnored() {
        let candidate = Track(title: "Shape of You!", artist: "Ed Sheeran", duration: 233)
        let result = LyricsResult(trackName: "shape of you", artistName: "Ed Sheeran", duration: 233, plainLyrics: "lyrics")
        #expect(validator.isValid(candidate: candidate, result: result))
    }

    @Test("a dash-remaster suffix on the canonical title still matches the played title (#326)")
    func dashRemasterSuffixMatches() {
        let candidate = Track(title: "Yesterday", artist: "The Beatles", duration: 125)
        let result = LyricsResult(
            trackName: "Yesterday - Remastered 2009", artistName: "The Beatles", duration: 125, plainLyrics: "lyrics")
        #expect(validator.isValid(candidate: candidate, result: result))
    }

    @Test("a parenthetical remaster suffix still matches (#326)")
    func parentheticalRemasterSuffixMatches() {
        let candidate = Track(title: "Bohemian Rhapsody", artist: "Queen", duration: 355)
        let result = LyricsResult(
            trackName: "Bohemian Rhapsody (Remastered 2011)", artistName: "Queen", duration: 355, plainLyrics: "lyrics")
        #expect(validator.isValid(candidate: candidate, result: result))
    }

    @Test("a candidate that itself carries a suffix matches the plain canonical title (#326)")
    func candidateSuffixMatchesPlainResult() {
        let candidate = Track(title: "Imagine - Remastered", artist: "John Lennon", duration: 183)
        let result = LyricsResult(trackName: "Imagine", artistName: "John Lennon", duration: 183, plainLyrics: "lyrics")
        #expect(validator.isValid(candidate: candidate, result: result))
    }

    @Test("a shorter title sharing only a character prefix is invalid — word boundaries are respected (#326)")
    func partialWordPrefixIsInvalid() {
        let candidate = Track(title: "Yes", artist: "Yes", duration: 200)
        let result = LyricsResult(trackName: "Yesterday", artistName: "The Beatles", duration: 200, plainLyrics: "lyrics")
        #expect(!validator.isValid(candidate: candidate, result: result))
    }

    // MARK: - Reason accessors for the debug log (#331)

    @Test("titleSimilarity is 1.0 for identical normalized titles")
    func titleSimilarityIdentical() {
        let candidate = Track(title: "Yesterday", artist: "The Beatles", duration: 125)
        let result = LyricsResult(trackName: "Yesterday", artistName: "The Beatles", duration: 125)
        #expect(validator.titleSimilarity(candidate: candidate, result: result) == 1.0)
    }

    @Test("titleSimilarity is nil when the result carries no title")
    func titleSimilarityNilWithoutResultTitle() {
        let candidate = Track(title: "Yesterday", artist: "The Beatles", duration: 125)
        let result = LyricsResult(trackName: nil, duration: 125)
        #expect(validator.titleSimilarity(candidate: candidate, result: result) == nil)
    }

    @Test("durationDelta reports the absolute difference")
    func durationDeltaValue() {
        let candidate = Track(title: "Yesterday", artist: "The Beatles", duration: 180)
        let result = LyricsResult(trackName: "Yesterday", artistName: "The Beatles", duration: 125)
        #expect(validator.durationDelta(candidate: candidate, result: result) == 55)
    }

    @Test("durationDelta is nil when either side lacks a duration")
    func durationDeltaNilWhenMissing() {
        let candidate = Track(title: "Yesterday", artist: "The Beatles", duration: nil)
        let result = LyricsResult(trackName: "Yesterday", artistName: "The Beatles", duration: 125)
        #expect(validator.durationDelta(candidate: candidate, result: result) == nil)
    }

    @Test("titles that normalize to empty (punctuation only) count as identical")
    func punctuationOnlyTitlesAreIdentical() {
        // Both titles strip to an empty normalized form, so similarity short-circuits to 1.
        let candidate = Track(title: "!!!", artist: "X", duration: nil)
        let result = LyricsResult(trackName: "???", duration: nil)
        #expect(validator.titleSimilarity(candidate: candidate, result: result) == 1.0)
    }

    // MARK: - Duration tolerance graduated by title confidence (#326)
    //
    // Every case below is a real rejection from the #331 trace log. An exact title is
    // strong evidence that this IS the song, so duration drops from a gate to a sanity
    // check; a merely-fuzzy title leaves duration as the only discriminator and stays
    // strict.

    @Test("an exact title survives a fade/edit-length difference — 白日, durΔ 12s (#326)")
    func exactTitleToleratesEditLengthDrift() {
        let candidate = Track(title: "白日", artist: "King Gnu", duration: 288)
        let result = LyricsResult(trackName: "白日", artistName: "King Gnu", duration: 276, plainLyrics: "lyrics")
        #expect(validator.isValid(candidate: candidate, result: result))
    }

    @Test("an exact title survives an album-vs-single length difference — 残響散歌, durΔ 46s (#326)")
    func exactTitleToleratesAlbumVersionDrift() {
        let candidate = Track(title: "残響散歌", artist: "Aimer", duration: 228)
        let result = LyricsResult(trackName: "残響散歌", artistName: "Aimer", duration: 182, plainLyrics: "lyrics")
        #expect(validator.isValid(candidate: candidate, result: result))
    }

    @Test("an exact title still rejects a live/medley-scale difference — Endless Rain, durΔ 463s (#326)")
    func exactTitleRejectsMedleyScaleDrift() {
        let candidate = Track(title: "Endless Rain", artist: "X JAPAN", duration: 859)
        let result = LyricsResult(trackName: "Endless Rain", artistName: "X JAPAN", duration: 396, plainLyrics: "lyrics")
        #expect(!validator.isValid(candidate: candidate, result: result))
    }

    @Test("an exact title still rejects a TV-size catalog entry — My Dearest, 336s vs 95s (#326)")
    func exactTitleRejectsTVSizeEntry() {
        let candidate = Track(title: "My Dearest", artist: "supercell", duration: 336)
        let result = LyricsResult(trackName: "My Dearest", artistName: "supercell", duration: 95, plainLyrics: "lyrics")
        #expect(!validator.isValid(candidate: candidate, result: result))
    }

    @Test("a merely-fuzzy title keeps the strict duration tolerance (#326)")
    func fuzzyTitleKeepsStrictDurationTolerance() {
        // "shapeofyou" vs "shapesofyou" clears the 0.6 similarity bar but is neither an
        // exact match nor a whole-token prefix, so duration stays the only discriminator.
        let candidate = Track(title: "Shape of You", artist: "Ed Sheeran", duration: 288)
        let result = LyricsResult(trackName: "Shapes of You", artistName: "Ed Sheeran", duration: 276, plainLyrics: "lyrics")
        #expect(!validator.isValid(candidate: candidate, result: result))
    }

    @Test("a remaster suffix carries the relaxed tolerance too — the remaster is a different cut (#326)")
    func remasterSuffixToleratesDurationDrift() {
        let candidate = Track(title: "Yesterday", artist: "The Beatles", duration: 145)
        let result = LyricsResult(
            trackName: "Yesterday - Remastered 2009", artistName: "The Beatles", duration: 125, plainLyrics: "lyrics")
        #expect(validator.isValid(candidate: candidate, result: result))
    }

    @Test("a non-positive duration means 'unknown', not a zero-length track — Numb 0s (#326)")
    func nonPositiveDurationIsTreatedAsUnknown() {
        // The media source reports 0 when it fails to read a duration. Comparing that as a
        // real length rejected every catalog entry and poisoned the cache on replay.
        let candidate = Track(title: "Numb", artist: "Linkin Park", duration: 0)
        let result = LyricsResult(trackName: "Numb", artistName: "Linkin Park", duration: 203, plainLyrics: "lyrics")
        #expect(validator.isValid(candidate: candidate, result: result))
        #expect(validator.durationDelta(candidate: candidate, result: result) == nil)
    }

    @Test("a short track keeps an absolute tolerance floor rather than a tiny ratio (#326)")
    func shortTrackKeepsToleranceFloor() {
        // 30% of a 30s interlude is 9s — below the floor, so the floor governs.
        let candidate = Track(title: "Interlude", artist: "X", duration: 45)
        let result = LyricsResult(trackName: "Interlude", artistName: "X", duration: 30, plainLyrics: "lyrics")
        #expect(validator.isValid(candidate: candidate, result: result))
    }
}
