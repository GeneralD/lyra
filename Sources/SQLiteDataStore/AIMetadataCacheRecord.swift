import GRDB

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
