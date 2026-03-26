import Dependencies
import Domain
import Presenters
import SwiftUI

private struct Column: Identifiable {
    let id: Int
    let entries: [(index: Int, displayText: String, sourceText: String)]
    let highlightIndex: Int?
}

@MainActor
public struct LyricsColumnView: View {
    @ObservedObject var presenter: LyricsPresenter

    public init(presenter: LyricsPresenter) {
        self.presenter = presenter
    }

    public var body: some View {
        GeometryReader { geo in
            let layout = ColumnLayout(width: geo.size.width, lyricsHeight: geo.size.height, lyricStyle: presenter.lyricStyle)
            if let content = presenter.lyricsState.value {
                let cols = columns(from: content, layout: layout)
                HStack(alignment: .top, spacing: layout.columnGap) {
                    ForEach(cols) { column in
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(column.entries, id: \.index) { entry in
                                LyricLineView(
                                    text: entry.displayText,
                                    isActive: entry.index == column.highlightIndex,
                                    lyricStyle: presenter.lyricStyle,
                                    highlightStyle: presenter.highlightStyle
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
        let sourceTexts: [String] =
            switch content {
            case .timed(let lines): lines.map(\.text)
            case .plain(let lines): lines
            }
        let displayTexts = presenter.displayLyricLines
        let highlightIndex: Int? =
            switch content {
            case .timed: presenter.activeLineIndex
            case .plain: nil
            }
        let lpc = layout.linesPerColumn
        let count = layout.columnsNeeded(for: sourceTexts.count)
        return (0..<count).map { col in
            let start = col * lpc
            let end = min(start + lpc, sourceTexts.count)
            let entries = (start..<end).map { i in
                (index: i, displayText: i < displayTexts.count ? displayTexts[i] : sourceTexts[i], sourceText: sourceTexts[i])
            }
            return Column(id: col, entries: entries, highlightIndex: highlightIndex)
        }
    }
}

#if DEBUG
    #Preview("Lyrics") {
        LyricsColumnView(presenter: LyricsPresenter())
            .frame(width: 600, height: 300)
            .background(.black)
    }
#endif
