import BackdropConfig
import BackdropDomain
import Dependencies
import SwiftUI

@MainActor
public struct HeaderView: View {
    let title: String?
    let artist: String?
    let artworkData: Data?

    @Dependency(\.config) private var config

    public init(title: String?, artist: String?, artworkData: Data?) {
        self.title = title
        self.artist = artist
        self.artworkData = artworkData
    }

    private var trackID: String { "\(title ?? "")\n\(artist ?? "")" }

    public var body: some View {
        let titleStyle = config.text.title
        let artistStyle = config.text.artist

        HStack(spacing: 24) {
            if let artworkData, let image = NSImage(data: artworkData) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: config.artwork.size)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: titleStyle.spacing) {
                if let title {
                    Text(title)
                        .font(makeFont(style: titleStyle))
                        .foregroundStyle(parseHexColor(titleStyle.colorHex))
                        .shadow(color: parseHexColor(titleStyle.shadowHex), radius: 5, x: 0, y: 1)
                        .lineLimit(1)
                }
                if let artist {
                    Text(artist)
                        .font(makeFont(style: artistStyle))
                        .foregroundStyle(parseHexColor(artistStyle.colorHex))
                        .shadow(color: parseHexColor(artistStyle.shadowHex), radius: 5, x: 0, y: 1)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .id(trackID)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.5), value: trackID)
    }
}
