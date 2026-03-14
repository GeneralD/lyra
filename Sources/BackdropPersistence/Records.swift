import BackdropDomain
import GRDB

struct LRCLibTrackRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "lrclib_tracks"

    let id: Int
    let trackName: String?
    let artistName: String?
    let albumName: String?
    let duration: Double?
    let instrumental: Bool?
    let plainLyrics: String?
    let syncedLyrics: String?

    enum CodingKeys: String, CodingKey {
        case id
        case trackName = "track_name"
        case artistName = "artist_name"
        case albumName = "album_name"
        case duration, instrumental
        case plainLyrics = "plain_lyrics"
        case syncedLyrics = "synced_lyrics"
    }

    init(from result: LyricsResult) {
        self.id = result.id ?? 0
        self.trackName = result.trackName
        self.artistName = result.artistName
        self.albumName = result.albumName
        self.duration = result.duration
        self.instrumental = result.instrumental
        self.plainLyrics = result.plainLyrics
        self.syncedLyrics = result.syncedLyrics
    }

    func toLyricsResult() -> LyricsResult {
        LyricsResult(
            id: id,
            trackName: trackName,
            artistName: artistName,
            albumName: albumName,
            duration: duration,
            instrumental: instrumental,
            plainLyrics: plainLyrics,
            syncedLyrics: syncedLyrics
        )
    }
}

struct LyricsLookupRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "lyrics_lookup"

    var id: Int64?
    let title: String
    let artist: String
    let lrclibId: Int

    enum CodingKeys: String, CodingKey {
        case id, title, artist
        case lrclibId = "lrclib_id"
    }
}
