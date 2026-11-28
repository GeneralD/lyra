import Domain
import GRDB

struct LRCLibTrackRecord {
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
}

extension LRCLibTrackRecord: Codable, FetchableRecord, PersistableRecord {
    static let lookups = hasMany(LyricsLookupRecord.self, using: ForeignKey(["lrclib_id"]))
}

extension LRCLibTrackRecord {
    init(from result: LyricsResult, id: Int) {
        self.init(
            id: id,
            trackName: result.trackName,
            artistName: result.artistName,
            albumName: result.albumName,
            duration: result.duration,
            instrumental: result.instrumental,
            plainLyrics: result.plainLyrics,
            syncedLyrics: result.syncedLyrics
        )
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
