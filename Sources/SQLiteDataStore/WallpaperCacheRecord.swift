import GRDB

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
