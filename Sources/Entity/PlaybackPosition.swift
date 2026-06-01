import Foundation

public struct PlaybackPosition {
    public let rawElapsed: TimeInterval?
    public let timestamp: Date?
    public let playbackRate: Double

    public init(
        rawElapsed: TimeInterval? = nil,
        timestamp: Date? = nil,
        playbackRate: Double = 1.0
    ) {
        self.rawElapsed = rawElapsed
        self.timestamp = timestamp
        self.playbackRate = playbackRate
    }
}

extension PlaybackPosition: Sendable {}
extension PlaybackPosition: Equatable {}
