// Copyright (C) 2026 GeneralD (yumejustice@gmail.com)
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

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