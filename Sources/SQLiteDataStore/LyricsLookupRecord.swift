import GRDB

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
