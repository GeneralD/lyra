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
}
