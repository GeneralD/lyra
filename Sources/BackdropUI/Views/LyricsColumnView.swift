import BackdropDomain
import BackdropPresentation
import CollectionKit
import SwiftUI

private struct Column: Identifiable {
    let id: Int
    let entries: [(index: Int, displayText: String, sourceText: String)]
    let highlightIndex: Int?
}

@MainActor
public struct LyricsColumnView: View {
    let state: OverlayState

    public init(state: OverlayState) {
        self.state = state
    }

    public var body: some View {
        GeometryReader { geo in
            let layout = ColumnLayout(width: geo.size.width, lyricsHeight: geo.size.height)
            if let content = state.lyrics.value {
                let cols = columns(from: content, layout: layout)
                HStack(alignment: .top, spacing: layout.columnGap) {
                    ForEach(cols) { column in
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(column.entries, id: \.index) { entry in
                                LyricLineView(
                                    text: entry.displayText,
                                    isActive: entry.index == column.highlightIndex
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
        let sourceTexts: [String] = switch content {
        case let .timed(lines): lines.map(\.text)
        case let .plain(lines): lines
        }
        let displayTexts = state.displayLyricLines
        let highlightIndex: Int? = switch content {
        case .timed: state.activeLineIndex
        case .plain: nil
        }
        let lpc = layout.linesPerColumn
        let count = layout.columnsNeeded(for: sourceTexts.count)
        return (0 ..< count).map { col in
            let start = col * lpc
            let end = min(start + lpc, sourceTexts.count)
            let entries = (start ..< end).map { i in
                (index: i, displayText: i < displayTexts.count ? displayTexts[i] : sourceTexts[i], sourceText: sourceTexts[i])
            }
            return Column(id: col, entries: entries, highlightIndex: highlightIndex)
        }
    }
}

#Preview("Lyrics") {
    LyricsColumnView(state: {
        let s = OverlayState()
        let lines: [LyricLine] = [
            .init(time: 0, text: "夜に駆ける"),
            .init(time: 5, text: "沈むように"),
            .init(time: 10, text: "溶けてゆくように"),
            .init(time: 15, text: "二人だけの空が広がる夜に"),
            .init(time: 20, text: "あなたの声が聞こえる"),
        ]
        s.lyrics = .success(.timed(lines))
        s.displayLyricLines = lines.map(\.text)
        s.activeLineIndex = 2
        return s
    }())
    .frame(width: 600, height: 300)
    .background(.black)
}
