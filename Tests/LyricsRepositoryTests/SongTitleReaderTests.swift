import Domain
import Testing

@testable import LyricsRepository

@Suite("SongTitleReader (#343)")
struct SongTitleReaderTests {
    private let reader = SongTitleReader()

    private func track(_ title: String, duration: Double? = 240) -> Track {
        Track(title: title, artist: "Channel", duration: duration)
    }

    // MARK: - Titles that pass through

    @Test("a plain song title is a song and is left alone")
    func plainTitle() {
        #expect(reader.read(track("Song")) == .song("Song"))
    }

    @Test("a title with no duration is not screened on runtime")
    func noDuration() {
        #expect(reader.read(track("Song", duration: nil)) == .song("Song"))
    }

    @Test("surrounding quotes are shaved off even without a marker")
    func quotedTitle() {
        #expect(reader.read(track("\u{201c}Song\u{201d}")) == .song("Song"))
    }

    @Test("a leading hyphen survives — it is part of the name, not leftover punctuation")
    func leadingHyphenKept() {
        #expect(reader.read(track("-ERROR 歌ってみた")) == .song("-ERROR"))
    }

    // MARK: - Cover normalization

    @Test(
        "cover markers are removed from the search title",
        arguments: [
            "Song 歌ってみた", "Song 唄ってみた", "Song うたってみた",
            "Song 叩いてみた", "Song 弾いてみた", "Song 演奏してみた",
            "Song (Cover)", "Song [cover]", "Song 【Cover】", "Song (カバー)",
            "Song | Band Cover", "Song / Piano Cover",
        ])
    func coverMarkersStripped(title: String) {
        #expect(reader.read(track(title)) == .song("Song"))
    }

    @Test("a hyphen separator is left behind — not trimming it is what keeps `-ERROR` intact")
    func hyphenSeparatorSurvivesStripping() {
        #expect(reader.read(track("Song - Drum Cover")) == .song("Song -"))
    }

    @Test("a quoted title wrapped in cover decoration comes back bare")
    func quotedCoverTitle() {
        #expect(reader.read(track("\"HONEY\" 叩いてみた | Drum Cover")) == .song("HONEY"))
    }

    @Test("`Covered by` truncates the performer credit that follows it")
    func coverCreditTruncated() {
        #expect(reader.read(track("Song Covered by 誰か")) == .song("Song"))
    }

    @Test("a title that is nothing but markers falls back to the raw title")
    func markersOnlyTitle() {
        #expect(reader.read(track("歌ってみた")) == .song("歌ってみた"))
    }

    // MARK: - Brackets survive the stripping intact

    @Test("a bracket left holding nothing is removed, not left stranded mid-title")
    func hollowBracketCollapses() {
        #expect(reader.read(track("【歌ってみた】終着")) == .song("終着"))
    }

    @Test("truncating a cover credit does not leave the bracket it cut through")
    func truncationDoesNotStrandAnOpener() {
        #expect(reader.read(track("Song (Covered by Someone)")) == .song("Song"))
    }

    @Test(
        "a bracket whose partner is nowhere in the title is shaved off either end",
        arguments: [("「Song", "Song"), ("Song」", "Song"), ("Song (", "Song"), (")Song", "Song")])
    func danglingBracketsShaved(input: String, expected: String) {
        #expect(reader.read(track(input)) == .song(expected))
    }

    @Test("a bracket that still has its partner is structure and stays")
    func matchedBracketsKept() {
        // The upstream candidate splitter feeds in half-titles like this; the reader must
        // not "tidy" a title that is merely quoting a work.
        #expect(reader.read(track("「作品名」 ノンクレジット映像")) == .song("「作品名」 ノンクレジット映像"))
        #expect(reader.read(track("アニメ『作品名』")) == .song("アニメ『作品名』"))
    }

    @Test("a pair wrapping the whole title is decoration and is unwrapped")
    func wholeTitleWrapUnwrapped() {
        #expect(reader.read(track("「Song」")) == .song("Song"))
    }

    // MARK: - Screening

    @Test("a clock range in the title is a broadcast, not a song")
    func broadcastClockRange() {
        guard case .notASong(let reason) = reader.read(track("11:55-12:00 | ニュース")) else {
            Issue.record("expected a broadcast screen")
            return
        }
        #expect(reason.contains("11:55-12:00"))
    }

    @Test("a calendar date in the title is a broadcast, not a song")
    func broadcastDate() {
        guard case .notASong(let reason) = reader.read(track("2026/08/16 の放送")) else {
            Issue.record("expected a broadcast screen")
            return
        }
        #expect(reason.contains("2026/08/16"))
    }

    // An instructional vocabulary (`解説`, `how to`, `tutorial`, …) used to screen here
    // and was removed in review (#344): matched as bare substrings those words also
    // occur inside real song titles, and a screen is unrecoverable — the candidate
    // never reaches either LRCLIB tier. These titles are what that cost looked like.
    @Test(
        "a title that merely reads instructionally is still searched",
        arguments: ["How to Save a Life", "検証", "入門", "Boys Don\u{2019}t Cry"])
    func instructionalWordingIsNotScreened(title: String) {
        #expect(reader.read(track(title)) == .song(title))
    }

    @Test("a runtime longer than any plausible song screens the title out")
    func overlongRuntime() {
        guard case .notASong(let reason) = reader.read(track("Live Stream", duration: 5400)) else {
            Issue.record("expected a runtime screen")
            return
        }
        #expect(reason.contains("5400s"))
    }

    @Test("the runtime bound is exclusive — a track exactly at the limit still counts as a song")
    func runtimeBoundIsExclusive() {
        #expect(reader.read(track("Song", duration: 1200)) == .song("Song"))
        #expect(reader.read(track("Song", duration: 1201)) != .song("Song"))
    }

    @Test("the runtime bound is configurable")
    func configurableRuntimeBound() {
        let strict = SongTitleReader(longestPlausibleSongSeconds: 300)
        #expect(strict.read(track("Song", duration: 600)) != .song("Song"))
    }

    // MARK: - Bracket structure survives normalization

    @Test("two sibling groups are structure, not a wrapper — matching ends alone prove nothing")
    func siblingGroupsAreNotUnwrapped() {
        // Naively "first and last character pair up" would strip these into `Song) (Live`
        // and `Song A」 / 「Song B`, corrupting a title that was never decorated (#344 review).
        #expect(reader.read(track("(Song) (Live)")) == .song("(Song) (Live)"))
        #expect(reader.read(track("\u{300c}Song A\u{300d} / \u{300c}Song B\u{300d}")) == .song("\u{300c}Song A\u{300d} / \u{300c}Song B\u{300d}"))
    }

    @Test("a pair that really does wrap the whole title is decoration and comes off")
    func wholeTitleWrapperIsUnwrapped() {
        #expect(reader.read(track("\u{300c}Song\u{300d}")) == .song("Song"))
        #expect(reader.read(track("\u{3010}Song\u{3011}")) == .song("Song"))
    }

    @Test("a nested pair inside a wrapper does not fool the depth check")
    func nestedPairInsideWrapperIsStillAWrapper() {
        #expect(reader.read(track("(Song (Live))")) == .song("Song (Live)"))
    }

    // MARK: - A cover marker outranks every screen

    @Test("a cover marker beats the runtime screen — a long take is still a performance")
    func coverBeatsRuntime() {
        #expect(reader.read(track("Song 叩いてみた", duration: 5400)) == .song("Song"))
    }

    @Test("a cover marker beats the broadcast screen — a dated upload is still a performance")
    func coverBeatsBroadcastStamp() {
        #expect(reader.read(track("Song 叩いてみた 2026/08/16")) == .song("Song 2026/08/16"))
    }
}
