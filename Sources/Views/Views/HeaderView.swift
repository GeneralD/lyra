import Config
import Domain
import Presentation
import Dependencies
import SwiftUI

@MainActor
public struct HeaderView: View {
    let state: OverlayState

    @Dependency(\.config) private var config

    public init(state: OverlayState) {
        self.state = state
    }

    public var body: some View {
        if !state.title.isIdle {
            let artworkSize = config.artwork.size
            let artworkOpacity = config.artwork.opacity

            HStack(spacing: artworkOpacity > 0 ? 24 : 0) {
                if artworkOpacity > 0 {
                    if let artworkData = state.artworkData, let image = NSImage(data: artworkData) {
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
                    Text(state.displayTitle)
                        .font(makeFont(style: config.text.title))
                        .foregroundStyle(config.text.title.color.shapeStyle)
                        .shadow(color: config.text.title.shadow.solidColor, radius: 5, x: 0, y: 1)
                        .lineLimit(1)
                    Text(state.displayArtist)
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
    withDependencies { $0.config = .init() } operation: {
        HeaderView(state: {
            let s = OverlayState()
            s.title = .success("See You Again")
            s.artist = .success("Wiz Khalifa")
            s.displayTitle = "See You Again"
            s.displayArtist = "Wiz Khalifa"
            return s
        }())
        .padding()
        .background(.black)
    }
}
#endif
