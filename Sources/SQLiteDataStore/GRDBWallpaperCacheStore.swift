import Domain
import GRDB

public struct GRDBWallpaperCacheStore: WallpaperCacheStore, Sendable {
    private let dbManager: DatabaseManager

    public init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }

    public func read(url: String) async -> WallpaperCacheEntry? {
        try? await dbManager.dbQueue.read { db in
            guard
                let record =
                    try WallpaperCacheRecord
                    .filter(Column("url") == url)
                    .fetchOne(db)
            else { return nil }
            return WallpaperCacheEntry(contentHash: record.contentHash, fileExt: record.fileExt)
        }
    }

    public func write(url: String, contentHash: String, fileExt: String) async throws {
        try await dbManager.dbQueue.write { db in
            try WallpaperCacheRecord(url: url, contentHash: contentHash, fileExt: fileExt)
                .save(db, onConflict: .replace)
        }
    }
}
