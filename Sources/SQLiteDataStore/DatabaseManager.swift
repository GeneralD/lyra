import Files
import Foundation
import GRDB

public final class DatabaseManager: Sendable {
    public let dbQueue: DatabaseQueue

    public init(cacheFolder: Folder? = nil) throws {
        let lyra = try cacheFolder ?? Folder.defaultCache.createSubfolderIfNeeded(withName: "lyra")
        let file = try lyra.createFileIfNeeded(withName: "database")
        dbQueue = try DatabaseQueue(path: file.path)
        try migrator.migrate(dbQueue)
    }

    // In-memory database for testing
    public init(inMemory: Bool) throws {
        dbQueue = try DatabaseQueue()
        try migrator.migrate(dbQueue)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_createTables") { db in
            // Drop legacy single-table schema
            try db.execute(sql: "DROP TABLE IF EXISTS lyrics")

            try db.create(table: "lrclib_tracks", ifNotExists: true) { t in
                t.primaryKey("id", .integer)
                t.column("track_name", .text)
                t.column("artist_name", .text)
                t.column("album_name", .text)
                t.column("duration", .double)
                t.column("instrumental", .boolean)
                t.column("plain_lyrics", .text)
                t.column("synced_lyrics", .text)
            }

            try db.create(table: "lyrics_lookup", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("title", .text).notNull()
                t.column("artist", .text).notNull()
                t.column("lrclib_id", .integer).notNull()
                    .references("lrclib_tracks", onDelete: .cascade)
                t.uniqueKey(["title", "artist"])
            }
        }

        migrator.registerMigration("v2_musicbrainzCache") { db in
            try db.create(table: "musicbrainz_cache", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("query_title", .text).notNull()
                t.column("query_artist", .text).notNull()
                t.column("resolved_title", .text).notNull()
                t.column("resolved_artist", .text).notNull()
                t.column("duration", .double)
                t.column("musicbrainz_id", .text).notNull()
                t.uniqueKey(["query_title", "query_artist"])
            }
        }

        migrator.registerMigration("v3_aiMetadataCache") { db in
            try db.create(table: "ai_metadata_cache", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("raw_title", .text).notNull()
                t.column("raw_artist", .text).notNull()
                t.column("resolved_title", .text).notNull()
                t.column("resolved_artist", .text).notNull()
                t.uniqueKey(["raw_title", "raw_artist"])
            }
        }

        migrator.registerMigration("v4_wallpaperCache") { db in
            try db.create(table: "wallpaper_cache", ifNotExists: true) { t in
                t.column("url", .text).primaryKey()
                t.column("content_hash", .text).notNull()
                t.column("file_ext", .text).notNull()
            }
        }

        migrator.registerMigration("v1_removeLegacyCache") { _ in
            try? Folder.defaultCache.subfolder(named: "now-playing").delete()
        }

        return migrator
    }
}
