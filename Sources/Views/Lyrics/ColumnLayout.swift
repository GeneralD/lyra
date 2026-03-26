import Dependencies
import Domain

public struct ColumnLayout {
    public let columnWidth: Double
    public let columnGap: Double
    public let maxColumns: Int
    public let linesPerColumn: Int

    @MainActor
    public init(width: Double, lyricsHeight: Double) {
        @Dependency(\.appStyle) var config
        @Dependency(\.fontMetrics) var fontMetrics
        let lyric = config.text.lyric
        let lineHeight = fontMetrics.lineHeight(fontName: lyric.fontName, fontSize: lyric.fontSize, spacing: lyric.spacing)

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
