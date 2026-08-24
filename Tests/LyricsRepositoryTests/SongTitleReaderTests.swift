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

    @Test(
        "an instructional marker screens the title out",
        arguments: ["解説", "講座", "レクチャー", "教則", "要約", "実況", "検証", "開封", "入門", "講義"])
    func japaneseNonSongMarkers(marker: String) {
        guard case .notASong(let reason) = reader.read(track("ドラム\(marker)")) else {
            Issue.record("expected \(marker) to screen the title out")
            return
        }
        #expect(reason.contains(marker))
    }

    @Test("English instructional markers match case-insensitively")
    func englishNonSongMarkers() {
        #expect(reader.read(track("How To Play Drums")) != .song("How To Play Drums"))
        #expect(reader.read(track("Cymbal UNBOXING")) != .song("Cymbal UNBOXING"))
        #expect(reader.read(track("Drum Tutorial")) != .song("Drum Tutorial"))
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

    // MARK: - A cover marker outranks every screen

    @Test("a cover marker beats the runtime screen — a long take is still a performance")
    func coverBeatsRuntime() {
        #expect(reader.read(track("Song 叩いてみた", duration: 5400)) == .song("Song"))
    }

    @Test("a cover marker beats an instructional marker — the video is a performance, not a lesson")
    func coverBeatsNonSongMarker() {
        #expect(reader.read(track("Song 叩いてみた【解説付き】")) == .song("Song 【解説付き】"))
    }
}
