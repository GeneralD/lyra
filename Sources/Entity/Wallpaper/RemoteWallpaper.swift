import Foundation

public struct RemoteWallpaper {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }
}

extension RemoteWallpaper: Sendable {}
