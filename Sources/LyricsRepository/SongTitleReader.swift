import Domain
import Foundation

// What a candidate's title is worth asking a lyrics catalog about.
enum SongTitle: Equatable {
    // Worth searching, using this as the catalog's track name. The associated string is
    // the played title with its video decoration removed, which is frequently the raw
    // title unchanged.
    case song(String)
    // No lyrics catalog will ever hold this. The associated string is a trace reason for
    // the resolution log (#331), not a user-facing message.
    case notASong(String)
}

// Reads a *media* title well enough to decide whether a lyrics catalog could hold it and
// what to ask for. The two are one job because the same vocabulary answers both: a title
// carrying `叩いてみた` is a song (so the not-a-song screen must not fire) *and* needs that
// marker removed before the search (#343).
//
// Measured against the resolution trace log, over the 980 distinct candidates whose Tier B
// search came back with nothing: 97 (9.9%) are screened out here as things no lyrics
// catalog holds — radio programmes, lessons, hours-long streams — and 238 (24.3%) have
// their title rewritten, almost all of them covers whose *title*, never their artist,
// carried the decoration that made the search miss. That is reach, not recall: a rewritten
// title still has to find a match.
//
// Deliberately conservative. A false positive here drops a real song, so this screens only
// on evidence that is hard to misread: a broadcast timestamp, an explicit instructional
// marker, a runtime no song has. Gear reviews titled plainly (`MEINL`) are not caught by
// design — widening the net to reach them would start costing real songs.
struct SongTitleReader {
    let longestPlausibleSongSeconds: Double

    init(longestPlausibleSongSeconds: Double = 1200) {
        self.longestPlausibleSongSeconds = longestPlausibleSongSeconds
    }

    func read(_ track: Track) -> SongTitle {
        // A cover marker is positive evidence of a song and outranks every screen below.
        // `"HONEY" 叩いてみた | Drum Cover` talks about drums the way a gear review does,
        // but it is a performance of a real song and its lyrics are the original's.
        guard !Self.isCover(track.title) else { return .song(Self.stripped(track.title)) }
        guard let reason = notASongReason(track) else { return .song(Self.stripped(track.title)) }
        return .notASong(reason)
    }
}

// MARK: - Screening

extension SongTitleReader {
    private func notASongReason(_ track: Track) -> String? {
        if let stamp = Self.broadcastStamp(track.title) { return "broadcast stamp '\(stamp)'" }
        if let marker = Self.nonSongMarker(track.title) { return "non-song marker '\(marker)'" }
        guard let duration = track.duration, duration > longestPlausibleSongSeconds else { return nil }
        return String(format: "runtime %.0fs", duration)
    }

    // A clock range or a calendar date in the title is a programme, not a song — the log's
    // `2026/08/16/日 11:55-12:00 | JFNニュース |` shape. Songs do not carry either.
    private static func broadcastStamp(_ title: String) -> String? {
        let patterns = [
            #"\d{1,2}:\d{2}\s*[-–—~〜]\s*\d{1,2}:\d{2}"#,
            #"\d{4}/\d{1,2}/\d{1,2}"#,
        ]
        return patterns.lazy
            .compactMap { title.range(of: $0, options: .regularExpression) }
            .first
            .map { String(title[$0]) }
    }

    // Words that announce the video is *about* something rather than a performance of it.
    // Drawn from titles observed in the trace log, not guessed: extend this from measured
    // misses, since every addition is a chance to drop a real song.
    private static let nonSongMarkers = [
        "解説", "講座", "レクチャー", "教則", "要約", "実況", "検証", "開封",
        "使ってみた", "やってみた", "入門", "講義",
        "tutorial", "unboxing", "how to",
    ]

    private static func nonSongMarker(_ title: String) -> String? {
        nonSongMarkers.first { title.range(of: $0, options: .caseInsensitive) != nil }
    }
}

// MARK: - Cover markers

extension SongTitleReader {
    // Markers that identify a cover and are safe to delete outright.
    private static let coverMarkers = [
        "歌ってみた", "唄ってみた", "うたってみた",
        "叩いてみた", "弾いてみた", "演奏してみた",
        "band cover", "drum cover", "guitar cover", "bass cover", "piano cover",
        "(cover)", "[cover]", "【cover】", "(カバー)",
    ]

    // Credit forms where everything from the marker to the end of the title names the
    // performer, not the song: `ATARASHII GAKKO! Covered by 理芽` is the song plus a credit.
    private static let coverCreditMarkers = ["covered by", "cover by"]

    private static func isCover(_ title: String) -> Bool {
        (coverMarkers + coverCreditMarkers).contains { title.range(of: $0, options: .caseInsensitive) != nil }
    }
}

// MARK: - Normalization

extension SongTitleReader {
    // Stage one of the title normalization agreed in #343: remove explicit markers and the
    // separators and quotes they leave behind, and nothing else. Splitting on `|` or `／`
    // or dropping `【…】` wholesale would recover more, but it also mangles titles that use
    // those legitimately (`【MV】`-prefixed uploads, `君の名は。`), so that stage waits on a
    // measurement rather than being guessed at now.
    private static func stripped(_ title: String) -> String {
        let credited = truncatingCoverCredit(title)
        let bare = coverMarkers.reduce(credited) {
            $0.replacingOccurrences(of: $1, with: " ", options: .caseInsensitive)
        }
        let tidy = tidied(bare)
        // Stripping a title down to nothing means the markers *were* the title; the raw
        // form is a better search key than an empty string.
        return tidy.isEmpty ? title : tidy
    }

    private static func truncatingCoverCredit(_ title: String) -> String {
        guard
            let marker = coverCreditMarkers.lazy
                .compactMap({ title.range(of: $0, options: .caseInsensitive) })
                .min(by: { $0.lowerBound < $1.lowerBound })
        else { return title }
        return String(title[title.startIndex..<marker.lowerBound])
    }

    // Brackets and quotes come in pairs, and normalization has to know that. Measured over
    // the trace log's 980 zero-response candidates, treating each character as loose
    // punctuation damaged 81 of the 237 rewrites (34%): deleting `歌ってみた` from inside
    // `【…】` stranded a hollow `【 】` mid-title, and shaving a *leading* `「` left its `」`
    // behind on titles that carried no cover marker at all.
    private static let pairs: [(open: Character, close: Character)] = [
        ("【", "】"), ("（", "）"), ("(", ")"), ("[", "]"),
        ("「", "」"), ("『", "』"), ("\u{201c}", "\u{201d}"), ("\u{2018}", "\u{2019}"),
    ]

    // Characters safe to shave off an edge on sight: whitespace, segment separators, and
    // the symmetric quotes (whose two ends are the same character, so removing one cannot
    // strand the other). Hyphens are deliberately absent: `-ERROR` is a real song title,
    // and an edge hyphen is as likely to be part of the name as leftover punctuation.
    private static let trimmable = CharacterSet(charactersIn: " \t\u{3000}\"'|｜∥/／")

    // Each reduction leaves the title the same length or shorter and none undoes another,
    // so applying them to a fixed point terminates; the depth bound is a backstop, not the
    // mechanism. One pass is not enough — collapsing a hollow `【 】` is what exposes the
    // whitespace at the edge that the trim then takes.
    private static func tidied(_ text: String, depth: Int = 8) -> String {
        guard depth > 0 else { return text }
        let reduced = [collapsedWhitespace, withoutHollowPairs, edgeTrimmed, withoutDanglingBracket, unwrapped]
            .reduce(text) { $1($0) }
        guard reduced != text else { return text }
        return tidied(reduced, depth: depth - 1)
    }

    private static func collapsedWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    // A pair with nothing left between it is what the marker deletion left behind.
    // Whitespace is already collapsed, so only the bare and single-space forms exist.
    private static func withoutHollowPairs(_ text: String) -> String {
        pairs.reduce(text) {
            $0.replacingOccurrences(of: "\($1.open)\($1.close)", with: "")
                .replacingOccurrences(of: "\($1.open) \($1.close)", with: "")
        }
    }

    private static func edgeTrimmed(_ text: String) -> String {
        text.trimmingCharacters(in: trimmable)
    }

    // A bracket whose partner appears nowhere in the title is punctuation something cut
    // through, and it can be left at either end by either cut: the cover-credit truncation
    // strands an opener (`…mizuki (Covered by …)` → `…mizuki (`), while the candidate
    // splitter upstream slices one title into `「悪魔の子` and `ヒグチアイ」 covered by …`,
    // stranding one of each. A bracket that still has its partner is structure, and stays.
    private static func withoutDanglingBracket(_ text: String) -> String {
        guard let first = text.first, let last = text.last else { return text }
        if let mate = partner(of: last), !text.dropLast().contains(mate) { return String(text.dropLast()) }
        if let mate = partner(of: first), !text.dropFirst().contains(mate) { return String(text.dropFirst()) }
        return text
    }

    private static func partner(of character: Character) -> Character? {
        if let pair = pairs.first(where: { $0.open == character }) { return pair.close }
        return pairs.first { $0.close == character }?.open
    }

    // A pair wrapping the *whole* title is decoration; one wrapping only part of it is
    // structure. `「葬送のフリーレン」 2ndクール…` keeps both halves because it does not end
    // where it opened.
    private static func unwrapped(_ text: String) -> String {
        guard text.count > 2, let first = text.first, let last = text.last,
            pairs.contains(where: { $0.open == first && $0.close == last })
        else { return text }
        return String(text.dropFirst().dropLast())
    }
}
