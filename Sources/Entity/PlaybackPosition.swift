import Foundation

public struct PlaybackPosition {
    public let elapsed: TimeInterval?
    public let playbackRate: Double

    public init(elapsed: TimeInterval? = nil, playbackRate: Double = 1.0) {
        self.elapsed = elapsed
        self.playbackRate = playbackRate
    }
}

extension PlaybackPosition: Sendable {}
