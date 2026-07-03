import Foundation

public struct NowPlaying {
    public let title: String?
    public let artist: String?
    public let artworkData: Data?
    public let duration: TimeInterval?
    public let rawElapsed: TimeInterval?
    public let playbackRate: Double
    public let timestamp: Date?
    /// Process id of the app that owns the now-playing session. Lets a
    /// consumer scope per-process work (e.g. a CoreAudio process tap for the
    /// spectrum analyzer, #23) to exactly the audio source. `nil` when
    /// MediaRemote reports no owning app.
    public let pid: Int?

    public init(
        title: String?,
        artist: String?,
        artworkData: Data?,
        duration: TimeInterval?,
        rawElapsed: TimeInterval?,
        playbackRate: Double,
        timestamp: Date?,
        pid: Int? = nil
    ) {
        self.title = title
        self.artist = artist
        self.artworkData = artworkData
        self.duration = duration
        self.rawElapsed = rawElapsed
        self.playbackRate = playbackRate
        self.timestamp = timestamp
        self.pid = pid
    }
}

extension NowPlaying: Sendable {}
extension NowPlaying: Equatable {}
