import Testing
@testable import BackdropDomain

@Suite("TitleParser")
struct TitleParserTests {
    let parser = TitleParser()

    @Test("strips brackets of all types")
    func stripBrackets() {
        #expect(parser.stripBrackets("Song (feat. Artist)") == "Song")
        #expect(parser.stripBrackets("Song【Official】") == "Song")
        #expect(parser.stripBrackets("Song [MV]") == "Song")
        #expect(parser.stripBrackets("Song「Live」") == "Song")
        #expect(parser.stripBrackets("Song（Full）") == "Song")
    }

    @Test("detects noise words")
    func isNoise() {
        #expect(parser.isNoise("Official Video"))
        #expect(parser.isNoise("MV"))
        #expect(parser.isNoise("VEVO"))
        #expect(parser.isNoise(""))
        #expect(parser.isNoise("  "))
        #expect(!parser.isNoise("Actual Song Title"))
    }

    @Test("splits title by common separators")
    func splitTitle() {
        #expect(parser.splitTitle("Artist - Song") == ["Artist", "Song"])
        #expect(parser.splitTitle("Artist / Song") == ["Artist", "Song"])
        #expect(parser.splitTitle("Artist | Song") == ["Artist", "Song"])
        #expect(parser.splitTitle("Artist｜Song") == ["Artist", "Song"])
    }

    @Test("generates candidates with artist")
    func candidatesWithArtist() {
        let candidates = parser.generateCandidates(title: "Song Title", artist: "Artist")
        #expect(!candidates.isEmpty)
        #expect(candidates[0] == SearchCandidate(title: "Song Title", artist: "Artist"))
    }

    @Test("generates candidates from dash-separated title")
    func candidatesFromDashTitle() {
        let candidates = parser.generateCandidates(title: "Artist - Song", artist: "Topic")
        #expect(candidates.contains(SearchCandidate(title: "Song", artist: "Artist")))
        #expect(candidates.contains(SearchCandidate(title: "Artist", artist: "Song")))
    }

    @Test("generates candidates without usable artist")
    func candidatesWithoutArtist() {
        let candidates = parser.generateCandidates(title: "Just a Song", artist: "")
        #expect(!candidates.isEmpty)
        #expect(candidates[0] == SearchCandidate(title: "Just a Song", artist: ""))
    }

    @Test("deduplicates candidates")
    func deduplication() {
        let candidates = parser.generateCandidates(title: "Song", artist: "Artist")
        let keys = candidates.map { "\($0.title.lowercased())|\($0.artist.lowercased())" }
        #expect(keys.count == Set(keys).count)
    }
}
