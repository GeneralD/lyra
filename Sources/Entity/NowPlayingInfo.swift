import Foundation

public struct NowPlayingInfo: Codable {
    public let title: String?
    public let artist: String?
    public let album: String?
    public let duration: TimeInterval?
    public let elapsedTime: TimeInterval?
    public let lyrics: String?
    public let syncedLyrics: [LyricLine]?
    public let currentLyric: String?

    public init(
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        duration: TimeInterval? = nil,
        elapsedTime: TimeInterval? = nil,
        lyrics: String? = nil,
        syncedLyrics: [LyricLine]? = nil,
        currentLyric: String? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsedTime = elapsedTime
        self.lyrics = lyrics
        self.syncedLyrics = syncedLyrics
        self.currentLyric = currentLyric
    }
}

extension NowPlayingInfo: Sendable {}
