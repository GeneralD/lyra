import Foundation
import GRDB

public final class DatabaseManager: Sendable {
    public let dbQueue: DatabaseQueue

    public init() throws {
        let cacheDir = URL(fileURLWithPath:
            ProcessInfo.processInfo.environment["XDG_CACHE_HOME"]
                ?? "\(NSHomeDirectory())/.cache"
        )
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let dbPath = cacheDir.appendingPathComponent("lyrics.db").path
        dbQueue = try DatabaseQueue(path: dbPath)
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

        migrator.registerMigration("v1_removeLegacyCache") { _ in
            let cacheDir = URL(fileURLWithPath:
                ProcessInfo.processInfo.environment["XDG_CACHE_HOME"]
                    ?? "\(NSHomeDirectory())/.cache"
            )
            try? FileManager.default.removeItem(at: cacheDir.appendingPathComponent("now-playing"))
        }

        return migrator
    }
}
