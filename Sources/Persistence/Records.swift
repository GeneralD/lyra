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

extension LRCLibTrackRecord: Codable, FetchableRecord, PersistableRecord {}

extension LRCLibTrackRecord {
    init(from result: LyricsResult) {
        self.init(
            id: result.id ?? 0,
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

struct LyricsLookupRecord {
    var id: Int64?
    let title: String
    let artist: String
    let lrclibId: Int

    enum CodingKeys: String, CodingKey {
        case id, title, artist
        case lrclibId = "lrclib_id"
    }
}

extension LyricsLookupRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "lyrics_lookup"
}

struct MusicBrainzCacheRecord {
    var id: Int64?
    let queryTitle: String
    let queryArtist: String
    let resolvedTitle: String
    let resolvedArtist: String
    let duration: Double?
    let musicbrainzId: String

    enum CodingKeys: String, CodingKey {
        case id
        case queryTitle = "query_title"
        case queryArtist = "query_artist"
        case resolvedTitle = "resolved_title"
        case resolvedArtist = "resolved_artist"
        case duration
        case musicbrainzId = "musicbrainz_id"
    }
}

extension MusicBrainzCacheRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "musicbrainz_cache"
}
