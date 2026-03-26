import Dependencies
import Domain
import Presentation
import SwiftUI

@MainActor
public struct HeaderView: View {
    @ObservedObject var presenter: HeaderPresenter

    @Dependency(\.appStyle) private var config

    public init(presenter: HeaderPresenter) {
        self.presenter = presenter
    }

    public var body: some View {
        if presenter.titleState != .idle {
            let artworkSize = config.artwork.size
            let artworkOpacity = config.artwork.opacity

            HStack(spacing: artworkOpacity > 0 ? 24 : 0) {
                if artworkOpacity > 0 {
                    if let artworkData = presenter.artworkData, let image = NSImage(data: artworkData) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: artworkSize)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .opacity(artworkOpacity)
                    } else {
                        Color.clear
                            .frame(width: artworkSize, height: artworkSize)
                    }
                }
                VStack(alignment: .leading, spacing: config.text.title.spacing) {
                    Text(presenter.displayTitle)
                        .font(makeFont(style: config.text.title))
                        .foregroundStyle(config.text.title.color.shapeStyle)
                        .shadow(color: config.text.title.shadow.solidColor, radius: 5, x: 0, y: 1)
                        .lineLimit(1)
                    Text(presenter.displayArtist)
                        .font(makeFont(style: config.text.artist))
                        .foregroundStyle(config.text.artist.color.shapeStyle)
                        .shadow(color: config.text.artist.shadow.solidColor, radius: 5, x: 0, y: 1)
                        .lineLimit(1)
                }
                Spacer()
            }
        }
    }
}

#if DEBUG
    #Preview("Header") {
        withDependencies {
            $0.appStyle = .init()
        } operation: {
            HeaderView(presenter: HeaderPresenter())
                .padding()
                .background(.black)
        }
    }
#endif
