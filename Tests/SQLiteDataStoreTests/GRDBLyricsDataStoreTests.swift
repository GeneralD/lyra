import Testing

@testable import Domain
@testable import SQLiteDataStore

@Suite("GRDBLyricsDataStore")
struct GRDBLyricsDataStoreTests {
    @Test("round-trip write and read")
    func writeAndRead() async throws {
        let db = try DatabaseManager(inMemory: true)
        let cache = GRDBLyricsDataStore(dbManager: db)

        let result = LyricsResult(
            id: 42,
            trackName: "Song",
            artistName: "Artist",
            albumName: "Album",
            duration: 240,
            instrumental: false,
            plainLyrics: "Hello world",
            syncedLyrics: "[00:01.00] Hello world"
        )

        try await cache.write(title: "song", artist: "artist", result: result)
        let read = await cache.read(title: "song", artist: "artist")

        #expect(read != nil)
        #expect(read?.id == 42)
        #expect(read?.trackName == "Song")
        #expect(read?.syncedLyrics == "[00:01.00] Hello world")
    }

    @Test("returns nil for missing entry")
    func readMissing() async throws {
        let db = try DatabaseManager(inMemory: true)
        let cache = GRDBLyricsDataStore(dbManager: db)

        let result = await cache.read(title: "nonexistent", artist: "nobody")
        #expect(result == nil)
    }

    @Test("id-less result with lyrics is cached under a synthetic negative id")
    func writeWithNilIdAndLyrics() async throws {
        let db = try DatabaseManager(inMemory: true)
        let cache = GRDBLyricsDataStore(dbManager: db)

        let result = LyricsResult(
            id: nil,
            trackName: "Script Song",
            artistName: "Script Artist",
            albumName: nil,
            duration: nil,
            instrumental: nil,
            plainLyrics: "custom script lyrics",
            syncedLyrics: nil
        )

        try await cache.write(title: "script song", artist: "script artist", result: result)
        let read = await cache.read(title: "script song", artist: "script artist")

        #expect(read?.plainLyrics == "custom script lyrics")
        #expect(read?.trackName == "Script Song")
        #expect((read?.id ?? 0) < 0)
    }

    @Test("rewriting the same id-less result converges on one row")
    func rewriteWithNilIdReplacesRow() async throws {
        let db = try DatabaseManager(inMemory: true)
        let cache = GRDBLyricsDataStore(dbManager: db)

        let first = LyricsResult(
            id: nil, trackName: "Song", artistName: "Artist", albumName: nil,
            duration: nil, instrumental: nil, plainLyrics: "v1", syncedLyrics: nil
        )
        let second = LyricsResult(
            id: nil, trackName: "Song", artistName: "Artist", albumName: nil,
            duration: nil, instrumental: nil, plainLyrics: "v2", syncedLyrics: nil
        )

        try await cache.write(title: "song", artist: "artist", result: first)
        try await cache.write(title: "song", artist: "artist", result: second)

        let read = await cache.read(title: "song", artist: "artist")
        let rows = try await db.dbQueue.read { try LRCLibTrackRecord.fetchCount($0) }
        #expect(read?.plainLyrics == "v2")
        #expect(rows == 1)
    }

    @Test("ignores id-less write with no lyrics content")
    func writeWithNilIdAndNoContent() async throws {
        let db = try DatabaseManager(inMemory: true)
        let cache = GRDBLyricsDataStore(dbManager: db)

        try await cache.write(title: "test", artist: "test", result: .empty)
        let result = await cache.read(title: "test", artist: "test")
        #expect(result == nil)
    }
}
