import Foundation

public struct WallpaperState {
    public let url: URL?
    public let start: TimeInterval?
    public let end: TimeInterval?

    public init(url: URL? = nil, start: TimeInterval? = nil, end: TimeInterval? = nil) {
        self.url = url
        self.start = start
        self.end = end
    }
}

extension WallpaperState: Sendable {}
