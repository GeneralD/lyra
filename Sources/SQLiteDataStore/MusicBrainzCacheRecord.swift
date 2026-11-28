import GRDB

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
