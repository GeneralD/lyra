public struct TrackUpdate {
    public let title: String?
    public let artist: String?
    public let lyrics: LyricsContent?
    public let lyricsState: TrackLyricsState
    /// `true` while the title/artist are being resolved by the AI extractor
    /// (LLM cache miss with an AI endpoint configured). Presenters use it to
    /// show a "processing" indicator during the API round-trip; it is `false`
    /// for the raw, cache-hit, and resolved updates (#57).
    public let aiResolving: Bool

    public init(
        title: String? = nil,
        artist: String? = nil,
        lyrics: LyricsContent? = nil,
        lyricsState: TrackLyricsState = .idle,
        aiResolving: Bool = false
    ) {
        self.title = title
        self.artist = artist
        self.lyrics = lyrics
        self.lyricsState = lyricsState
        self.aiResolving = aiResolving
    }
}

extension TrackUpdate: Sendable {}
