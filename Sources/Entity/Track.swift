import Foundation

public struct Track {
    public let title: String
    public let artist: String
    public let duration: TimeInterval?

    public init(title: String, artist: String, duration: TimeInterval? = nil) {
        self.title = title
        self.artist = artist
        self.duration = duration
    }
}

extension Track: Sendable {}
extension Track: Equatable {}
