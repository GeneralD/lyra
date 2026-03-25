import Foundation

public enum LyricsContent {
    case timed([LyricLine])
    case plain([String])
}

extension LyricsContent: Sendable {}
extension LyricsContent: Equatable {}

extension LyricsContent {
    public init?(from result: LyricsResult?) {
        if let synced = result?.syncedLyrics.flatMap(Self.parseSyncedLyrics), !synced.isEmpty {
            self = .timed(synced)
            return
        }
        guard let plain = result?.plainLyrics else { return nil }
        self = .plain(plain.components(separatedBy: "\n"))
    }

    private static func parseSyncedLyrics(_ raw: String) -> [LyricLine] {
        let re = #/\[(\d+):(\d+(?:\.\d+)?)\]\s*(.*)/#
        return raw.split(separator: "\n").compactMap { line in
            guard let match = try? re.firstMatch(in: line),
                let min = Double(String(match.1)),
                let sec = Double(String(match.2))
            else { return nil }
            return LyricLine(
                time: min * 60 + sec,
                text: String(match.3).trimmingCharacters(in: .whitespaces)
            )
        }
    }
}
