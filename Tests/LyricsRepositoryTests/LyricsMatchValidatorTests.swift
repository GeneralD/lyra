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
}
