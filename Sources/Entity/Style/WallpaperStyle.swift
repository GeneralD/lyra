import Foundation

public struct WallpaperStyle {
    public let location: String
    public let start: TimeInterval?
    public let end: TimeInterval?

    public init(location: String, start: TimeInterval? = nil, end: TimeInterval? = nil) {
        self.location = location
        self.start = start
        self.end = end
    }
}

extension WallpaperStyle: Sendable {}
extension WallpaperStyle: Equatable {}
