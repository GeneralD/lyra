import Foundation

public enum LyricsContent: Sendable, Equatable {
    case timed([LyricLine])
    case plain([String])

    public init?(from result: LyricsResult?) {
        if let synced = result?.syncedLyrics.flatMap({ Self.parseSyncedLyrics($0) }), !synced.isEmpty {
            self = .timed(synced)
        } else if let plain = result?.plainLyrics {
            self = .plain(plain.components(separatedBy: "\n"))
        } else {
            return nil
        }
    }

    private static func parseSyncedLyrics(_ raw: String) -> [LyricLine] {
        let re = #/\[(\d+):(\d+(?:\.\d+)?)\]\s*(.*)/#
        return raw.split(separator: "\n").compactMap { line in
            guard let match = try? re.firstMatch(in: line),
                  let min = Double(String(match.1)),
                  let sec = Double(String(match.2)) else { return nil }
            return LyricLine(
                time: min * 60 + sec,
                text: String(match.3).trimmingCharacters(in: .whitespaces)
            )
        }
    }
}
