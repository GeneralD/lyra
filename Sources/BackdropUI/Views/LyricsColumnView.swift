import BackdropDomain
import CollectionKit
import SwiftUI

private struct Column: Identifiable {
    let id: Int
    let entries: [(index: Int, text: String)]
    let highlightIndex: Int?
}

@MainActor
public struct LyricsColumnView: View {
    let lyrics: FetchState<LyricsContent>
    let activeLineIndex: Int?

    public init(lyrics: FetchState<LyricsContent>, activeLineIndex: Int?) {
        self.lyrics = lyrics
        self.activeLineIndex = activeLineIndex
    }

    public var body: some View {
        GeometryReader { geo in
            let layout = ColumnLayout(width: geo.size.width, lyricsHeight: geo.size.height)
            if let content = lyrics.value {
                let cols = columns(from: content, layout: layout)
                HStack(alignment: .top, spacing: layout.columnGap) {
                    ForEach(cols) { column in
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(column.entries, id: \.index) { entry in
                                LyricLineView(
                                    text: entry.text,
                                    isActive: entry.index == column.highlightIndex,
                                    isRevealing: lyrics.isRevealing
                                )
                            }
                            Spacer()
                        }
                        .frame(width: layout.columnWidth)
                    }
                }
            }
        }
    }

    private func columns(from content: LyricsContent, layout: ColumnLayout) -> [Column] {
        let (texts, highlightIndex): ([String], Int?) = switch content {
        case let .timed(lines): (lines.map(\.text), activeLineIndex)
        case let .plain(lines): (lines, nil)
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
}
