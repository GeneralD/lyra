import BackdropDomain
import SwiftUI

struct Column: Identifiable {
    let id: Int
    let entries: [(index: Int, text: String)]
    let highlightIndex: Int?
}

@MainActor
public struct LyricsColumnView: View {
    let lyrics: LyricsContent?
    let activeLineIndex: Int?

    public init(lyrics: LyricsContent?, activeLineIndex: Int?) {
        self.lyrics = lyrics
        self.activeLineIndex = activeLineIndex
    }

    private func columns(layout: ColumnLayout) -> [Column] {
        let texts: [String]
        let highlightIndex: Int?
        switch lyrics {
        case let .timed(lines):
            texts = lines.map(\.text)
            highlightIndex = activeLineIndex
        case let .plain(lines):
            texts = lines
            highlightIndex = nil
        case nil:
            return []
        }
        let lpc = layout.linesPerColumn
        let count = layout.columnsNeeded(for: texts.count)
        return (0 ..< count).map { col in
            let start = col * lpc
            let end = min(start + lpc, texts.count)
            let entries = (start ..< end).map { i in (index: i, text: texts[i]) }
            return Column(id: col, entries: entries, highlightIndex: highlightIndex)
        }
    }

    public var body: some View {
        GeometryReader { geo in
            let layout = ColumnLayout(width: geo.size.width, lyricsHeight: geo.size.height)
            HStack(alignment: .top, spacing: layout.columnGap) {
                ForEach(columns(layout: layout)) { column in
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(column.entries, id: \.index) { entry in
                            LyricLineView(text: entry.text, isActive: entry.index == column.highlightIndex)
                        }
                        Spacer()
                    }
                    .frame(width: layout.columnWidth)
                }
            }
        }
    }
}
