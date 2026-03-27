import Foundation

public struct TrackUpdate {
    public let title: String?
    public let artist: String?
    public let artworkData: Data?
    public let duration: TimeInterval?
    public let lyrics: LyricsContent?
    public let lyricsState: TrackLyricsState

    public init(
        title: String? = nil,
        artist: String? = nil,
        artworkData: Data? = nil,
        duration: TimeInterval? = nil,
        lyrics: LyricsContent? = nil,
        lyricsState: TrackLyricsState = .idle
    ) {
        self.title = title
        self.artist = artist
        self.artworkData = artworkData
        self.duration = duration
        self.lyrics = lyrics
        self.lyricsState = lyricsState
    }
}

extension TrackUpdate: Sendable {}
