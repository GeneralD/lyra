public struct TrackUpdate {
    public let title: String?
    public let artist: String?
    public let lyrics: LyricsContent?
    public let lyricsState: TrackLyricsState

    public init(
        title: String? = nil,
        artist: String? = nil,
        lyrics: LyricsContent? = nil,
        lyricsState: TrackLyricsState = .idle
    ) {
        self.title = title
        self.artist = artist
        self.lyrics = lyrics
        self.lyricsState = lyricsState
    }
}

extension TrackUpdate: Sendable {}
