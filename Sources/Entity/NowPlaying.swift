import Foundation

public struct NowPlaying {
    public let title: String?
    public let artist: String?
    public let artworkData: Data?
    public let duration: TimeInterval?
    public let rawElapsed: TimeInterval?
    public let playbackRate: Double
    public let timestamp: Date?

    public init(
        title: String?,
        artist: String?,
        artworkData: Data?,
        duration: TimeInterval?,
        rawElapsed: TimeInterval?,
        playbackRate: Double,
        timestamp: Date?
    ) {
        self.title = title
        self.artist = artist
        self.artworkData = artworkData
        self.duration = duration
        self.rawElapsed = rawElapsed
        self.playbackRate = playbackRate
        self.timestamp = timestamp
    }
}

extension NowPlaying: Sendable {}
extension NowPlaying: Equatable {}
