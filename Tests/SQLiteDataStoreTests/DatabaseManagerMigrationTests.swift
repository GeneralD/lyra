import GRDB
import Testing

@testable import SQLiteDataStore

@Suite("DatabaseManager migrations")
struct DatabaseManagerMigrationSpec {
    @Test("in-memory database creates all required tables")
    func allTablesCreated() throws {
        let db = try DatabaseManager(inMemory: true)
        let tables = try db.dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
        }
        #expect(tables.contains("lrclib_tracks"))
        #expect(tables.contains("lyrics_lookup"))
        #expect(tables.contains("musicbrainz_cache"))
        #expect(tables.contains("ai_metadata_cache"))
        #expect(tables.contains("wallpaper_cache"))
    }

    @Test("lyrics_lookup has unique constraint on title+artist")
    func lyricsLookupUnique() throws {
        let db = try DatabaseManager(inMemory: true)
        try db.dbQueue.write { db in
            // Insert a track first
            try db.execute(
                sql: "INSERT INTO lrclib_tracks (id, track_name) VALUES (1, 'Song')"
            )
            try db.execute(
                sql: "INSERT INTO lyrics_lookup (title, artist, lrclib_id) VALUES ('Song', 'Artist', 1)"
            )
            // Duplicate should fail
            #expect(throws: (any Error).self) {
                try db.execute(
                    sql:
                        "INSERT INTO lyrics_lookup (title, artist, lrclib_id) VALUES ('Song', 'Artist', 1)"
                )
            }
        }
    }

    @Test("musicbrainz_cache has unique constraint on query_title+query_artist")
    func musicbrainzUnique() throws {
        let db = try DatabaseManager(inMemory: true)
        try db.dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO musicbrainz_cache
                    (query_title, query_artist, resolved_title, resolved_artist, musicbrainz_id)
                    VALUES ('Song', 'Artist', 'Song', 'Artist', 'id1')
                    """
            )
            #expect(throws: (any Error).self) {
                try db.execute(
                    sql: """
                        INSERT INTO musicbrainz_cache
                        (query_title, query_artist, resolved_title, resolved_artist, musicbrainz_id)
                        VALUES ('Song', 'Artist', 'Song2', 'Artist2', 'id2')
                        """
                )
            }
        }
    }

    @Test("wallpaper_cache uses url as primary key")
    func wallpaperPrimaryKey() throws {
        let db = try DatabaseManager(inMemory: true)
        try db.dbQueue.write { db in
            try db.execute(
                sql:
                    "INSERT INTO wallpaper_cache (url, content_hash, file_ext) VALUES ('https://a.com', 'hash1', 'mp4')"
            )
            #expect(throws: (any Error).self) {
                try db.execute(
                    sql:
                        "INSERT INTO wallpaper_cache (url, content_hash, file_ext) VALUES ('https://a.com', 'hash2', 'mp4')"
                )
            }
        }
    }

    @Test("migrations are idempotent — running twice does not error")
    func idempotent() throws {
        _ = try DatabaseManager(inMemory: true)
        _ = try DatabaseManager(inMemory: true)
    }
}
