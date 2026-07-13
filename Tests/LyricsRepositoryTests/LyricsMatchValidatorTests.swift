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
}
