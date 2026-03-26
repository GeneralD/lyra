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
    static let track = belongsTo(LRCLibTrackRecord.self, using: ForeignKey(["lrclib_id"]))
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

struct AIMetadataCacheRecord {
    var id: Int64?
    let rawTitle: String
    let rawArtist: String
    let resolvedTitle: String
    let resolvedArtist: String

    enum CodingKeys: String, CodingKey {
        case id
        case rawTitle = "raw_title"
        case rawArtist = "raw_artist"
        case resolvedTitle = "resolved_title"
        case resolvedArtist = "resolved_artist"
    }
}

extension AIMetadataCacheRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "ai_metadata_cache"
}

struct WallpaperCacheRecord {
    let url: String
    let contentHash: String
    let fileExt: String

    enum CodingKeys: String, CodingKey {
        case url
        case contentHash = "content_hash"
        case fileExt = "file_ext"
    }
}

extension WallpaperCacheRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "wallpaper_cache"
}
