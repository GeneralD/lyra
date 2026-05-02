import Foundation

public struct ResolvedWallpaperItem {
    public let url: URL
    public let start: TimeInterval?
    public let end: TimeInterval?
    public let scale: Double

    public init(
        url: URL,
        start: TimeInterval? = nil,
        end: TimeInterval? = nil,
        scale: Double = 1.0
    ) {
        self.url = url
        self.start = start
        self.end = end
        self.scale = scale.isFinite ? max(1.0, scale) : 1.0
    }
}

extension ResolvedWallpaperItem: Sendable {}
extension ResolvedWallpaperItem: Equatable {}

public struct WallpaperState {
    public let items: [ResolvedWallpaperItem]
    public let mode: WallpaperPlaybackMode

    public init(items: [ResolvedWallpaperItem] = [], mode: WallpaperPlaybackMode = .cycle) {
        self.items = items
        self.mode = mode
    }
}

extension WallpaperState: Sendable {}
extension WallpaperState: Equatable {}
