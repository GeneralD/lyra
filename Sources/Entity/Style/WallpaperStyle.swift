import Foundation

public struct WallpaperItem {
    public let location: String
    public let start: TimeInterval?
    public let end: TimeInterval?

    public init(location: String, start: TimeInterval? = nil, end: TimeInterval? = nil) {
        self.location = location
        self.start = start
        self.end = end
    }
}

extension WallpaperItem: Sendable {}
extension WallpaperItem: Equatable {}

public struct WallpaperStyle {
    public let items: [WallpaperItem]
    public let mode: WallpaperPlaybackMode

    public init(items: [WallpaperItem], mode: WallpaperPlaybackMode = .cycle) {
        self.items = items
        self.mode = mode
    }

    /// Convenience for single-item style (backward-compatible with legacy call sites).
    public init(location: String, start: TimeInterval? = nil, end: TimeInterval? = nil) {
        self.items = [WallpaperItem(location: location, start: start, end: end)]
        self.mode = .cycle
    }
}

extension WallpaperStyle: Sendable {}
extension WallpaperStyle: Equatable {}
