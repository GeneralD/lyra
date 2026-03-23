import Domain
import Testing
@testable import MetadataDataSource

@Suite("RegexNormalizer")
struct RegexNormalizerTests {
    let parser = RegexNormalizer()

    @Test("strips brackets of all types")
    func stripBrackets() {
        #expect(parser.stripBrackets("Song (feat. Artist)") == "Song")
        #expect(parser.stripBrackets("Song【Official】") == "Song")
        #expect(parser.stripBrackets("Song [MV]") == "Song")
        #expect(parser.stripBrackets("Song「Live」") == "Song「Live」")
        #expect(parser.stripBrackets("Song（Full）") == "Song")
    }

    @Test("normalizes YouTube-style titles")
    func normalize() {
        #expect(parser.normalize("Numb (Official Video)") == "Numb")
        #expect(parser.normalize("Numb (Live in Texas)") == "Numb")
        #expect(parser.normalize("Numb - 2003 Remaster") == "Numb")
        #expect(parser.normalize("Numb [HD]") == "Numb")
        #expect(parser.normalize("Song (Remastered 2020)") == "Song")
        #expect(parser.normalize("Hitori No Yoru (Cover)") == "Hitori No Yoru")
        #expect(parser.normalize("Song (Acoustic Cover)") == "Song")
    }

    @Test("normalizes titles with series/channel suffix")
    func normalizeWithSeries() {
        #expect(parser.normalize("Hello / THE FIRST TAKE") == "Hello")
        #expect(parser.normalize("Song (piano ver.) / Channel") == "Song")
    }

    @Test("normalizes artist names")
    func normalizeArtist() {
        #expect(parser.normalizeArtist("Linkin Park - Topic") == "Linkin Park")
        #expect(parser.normalizeArtist("ArtistVEVO") == "Artist")
        #expect(parser.normalizeArtist("Artist Official Channel") == "Artist")
        #expect(parser.normalizeArtist("Linkin Park") == "Linkin Park")
    }

    @Test("parses artist-title structure")
    func parseArtistTitle() {
        let result = parser.parseArtistTitle("Linkin Park - Numb (Live in Texas) / YouTube Music")
        #expect(result.artist == "Linkin Park")
        #expect(result.title == "Numb")
    }

    @Test("parses Japanese bracket title format")
    func parseJapaneseBracketTitle() {
        let result = parser.parseArtistTitle("L'Arc～en～Ciel「Driver's High」-Music Clip-")
        #expect(result.artist == "L'Arc～en～Ciel")
        #expect(result.title == "Driver's High")
    }

    @Test("parses double bracket format")
    func parseDoubleBracketTitle() {
        let result = parser.parseArtistTitle("Artist『Song Title』")
        #expect(result.artist == "Artist")
        #expect(result.title == "Song Title")
    }

    @Test("parseArtistTitle without dash returns nil artist")
    func parseArtistTitleNoDash() {
        let result = parser.parseArtistTitle("Just a Song (Official Video)")
        #expect(result.artist == nil)
        #expect(result.title == "Just a Song")
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
        #expect(candidates.contains(Track(title: "Song Title", artist: "Artist")))
    }

    @Test("generates candidates from YouTube-style title")
    func candidatesFromYouTubeTitle() {
        let candidates = parser.generateCandidates(
            title: "Linkin Park - Numb (Official Video)",
            artist: "Linkin Park - Topic"
        )
        #expect(candidates.contains(Track(title: "Numb", artist: "Linkin Park")))
    }

    @Test("generates candidates without usable artist")
    func candidatesWithoutArtist() {
        let candidates = parser.generateCandidates(title: "Just a Song", artist: "")
        #expect(!candidates.isEmpty)
        #expect(candidates[0] == Track(title: "Just a Song", artist: ""))
    }

    @Test("deduplicates candidates")
    func deduplication() {
        let candidates = parser.generateCandidates(title: "Song", artist: "Artist")
        let keys = candidates.map { "\($0.title.lowercased())|\($0.artist.lowercased())" }
        #expect(keys.count == Set(keys).count)
    }
}
