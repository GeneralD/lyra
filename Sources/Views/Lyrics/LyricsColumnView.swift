import Dependencies
import Domain
import Presenters
import SwiftUI

@MainActor
public struct LyricsColumnView: View {
    @ObservedObject var presenter: LyricsPresenter

    public init(presenter: LyricsPresenter) {
        self.presenter = presenter
    }

    public var body: some View {
        @Dependency(\.swiftUIResolver) var resolver

        GeometryReader { geo in
            let lineHeight = resolver.lineHeight(from: presenter.lyricStyle)
            let result = presenter.columns(in: geo.size, lineHeight: lineHeight)
            HStack(alignment: .top, spacing: result.columnGap) {
                ForEach(result.columns) { column in
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(column.entries) { entry in
                            LyricLineView(
                                text: entry.displayText,
                                isActive: entry.index == column.highlightIndex,
                                lyricStyle: presenter.lyricStyle,
                                highlightStyle: presenter.highlightStyle
                            )
                        }
                        Spacer()
                    }
                    .frame(width: result.columnWidth)
                }
            }
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
