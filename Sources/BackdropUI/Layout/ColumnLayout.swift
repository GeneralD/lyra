import BackdropDomain
import Dependencies

public struct ColumnLayout {
    public let columnWidth: Double
    public let columnGap: Double
    public let maxColumns: Int
    public let linesPerColumn: Int

    @MainActor
    public init(width: Double, lyricsHeight: Double) {
        @Dependency(\.config) var config
        let lineHeight = config.text.lyric.lineHeight

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
