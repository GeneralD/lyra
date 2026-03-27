// Copyright (C) 2026 GeneralD (yumejustice@gmail.com)
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

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

    @Test("ignores write with nil id")
    func writeWithNilId() async throws {
        let db = try DatabaseManager(inMemory: true)
        let cache = GRDBLyricsDataStore(dbManager: db)

        try await cache.write(title: "test", artist: "test", result: .empty)
        let result = await cache.read(title: "test", artist: "test")
        #expect(result == nil)
    }
}