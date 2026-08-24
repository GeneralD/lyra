public struct LyricsResult {
    public let id: Int?
    public let trackName: String?
    public let artistName: String?
    public let albumName: String?
    public let duration: Double?
    public let instrumental: Bool?
    public let plainLyrics: String?
    public let syncedLyrics: String?

    public init(
        id: Int? = nil,
        trackName: String? = nil,
        artistName: String? = nil,
        albumName: String? = nil,
        duration: Double? = nil,
        instrumental: Bool? = nil,
        plainLyrics: String? = nil,
        syncedLyrics: String? = nil
    ) {
        self.id = id
        self.trackName = trackName
        self.artistName = artistName
        self.albumName = albumName
        self.duration = duration
        self.instrumental = instrumental
        self.plainLyrics = plainLyrics
        self.syncedLyrics = syncedLyrics
    }

    public static let empty = LyricsResult()

    // Drops the synced timings, keeping the words. A cover runs at its own tempo and
    // length, so the original's timings scroll out of step with what is playing; the text
    // itself is still right (#343). When there is no plain copy to fall back on the
    // result is returned unchanged — silently having nothing to show would be worse than
    // showing timings that drift.
    public func withoutSyncedLyrics() -> LyricsResult {
        guard let plainLyrics, !plainLyrics.isEmpty else { return self }
        return LyricsResult(
            id: id, trackName: trackName, artistName: artistName, albumName: albumName,
            duration: duration, instrumental: instrumental,
            plainLyrics: plainLyrics, syncedLyrics: nil
        )
    }

    public func withDisplay(title: String, artist: String) -> LyricsResult {
        LyricsResult(
            id: id, trackName: title, artistName: artist, albumName: albumName,
            duration: duration, instrumental: instrumental,
            plainLyrics: plainLyrics, syncedLyrics: syncedLyrics
        )
    }
}

extension LyricsResult: Sendable {}
extension LyricsResult: Equatable {}
extension LyricsResult: Codable {}
