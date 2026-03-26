import Domain
import Presenters
import SwiftUI

@MainActor
public struct HeaderView: View {
    @ObservedObject var presenter: HeaderPresenter

    public init(presenter: HeaderPresenter) {
        self.presenter = presenter
    }

    public var body: some View {
        if presenter.titleState != .idle {
            HStack(spacing: presenter.artworkOpacity > 0 ? 24 : 0) {
                if presenter.artworkOpacity > 0 {
                    if let artworkData = presenter.artworkData, let image = NSImage(data: artworkData) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: presenter.artworkSize)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .opacity(presenter.artworkOpacity)
                    } else {
                        Color.clear
                            .frame(width: presenter.artworkSize, height: presenter.artworkSize)
                    }
                }
                VStack(alignment: .leading, spacing: presenter.titleStyle.spacing) {
                    Text(presenter.displayTitle)
                        .font(makeFont(style: presenter.titleStyle))
                        .foregroundStyle(presenter.titleStyle.color.shapeStyle)
                        .shadow(color: presenter.titleStyle.shadow.solidColor, radius: 5, x: 0, y: 1)
                        .lineLimit(1)
                    Text(presenter.displayArtist)
                        .font(makeFont(style: presenter.artistStyle))
                        .foregroundStyle(presenter.artistStyle.color.shapeStyle)
                        .shadow(color: presenter.artistStyle.shadow.solidColor, radius: 5, x: 0, y: 1)
                        .lineLimit(1)
                }
                Spacer()
            }
        }
    }
}

#if DEBUG
    #Preview("Header") {
        HeaderView(presenter: HeaderPresenter())
            .padding()
            .background(.black)
    }
#endif
