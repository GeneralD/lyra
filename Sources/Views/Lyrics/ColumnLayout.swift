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

import Dependencies
import Domain

public struct ColumnLayout {
    public let columnWidth: Double
    public let columnGap: Double
    public let maxColumns: Int
    public let linesPerColumn: Int

    @MainActor
    public init(width: Double, lyricsHeight: Double, lyricStyle: TextAppearance) {
        @Dependency(\.fontMetrics) var fontMetrics
        let lineHeight = fontMetrics.lineHeight(
            fontName: lyricStyle.fontName, fontSize: lyricStyle.fontSize, spacing: lyricStyle.spacing
        )

        columnGap = (width * 0.03).rounded()
        columnWidth = (width * 0.28).rounded()
        maxColumns = max(1, Int((width + columnGap) / (columnWidth + columnGap)))
        linesPerColumn = max(1, Int(lyricsHeight / lineHeight))
    }

    public func columnsNeeded(for lineCount: Int) -> Int {
        min(maxColumns, max(1, (lineCount + linesPerColumn - 1) / linesPerColumn))
    }
}

extension ColumnLayout: Sendable {}