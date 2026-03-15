import BackdropConfig
import BackdropDomain
import Dependencies
import SwiftUI

@MainActor
public struct HeaderView: View {
    let title: FetchState<String>
    let artist: FetchState<String>
    let artworkData: Data?

    @Dependency(\.config) private var config

    public init(title: FetchState<String>, artist: FetchState<String>, artworkData: Data?) {
        self.title = title
        self.artist = artist
        self.artworkData = artworkData
    }

    public var body: some View {
        HStack(spacing: 24) {
            if let artworkData, let image = NSImage(data: artworkData) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: config.artwork.size)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: config.text.title.spacing) {
                DecodeTextView(fetchState: title, style: config.text.title)
                DecodeTextView(fetchState: artist, style: config.text.artist)
            }
            Spacer()
        }
    }
}
