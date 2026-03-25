import Foundation

public struct YouTubeWallpaper {
    public let url: URL
    public let maxHeight: Int
    public let format: String

    public init(url: URL, maxHeight: Int = 2160, format: String = "mp4") {
        self.url = url
        self.maxHeight = maxHeight
        self.format = format
    }
}

extension YouTubeWallpaper: Sendable {}
