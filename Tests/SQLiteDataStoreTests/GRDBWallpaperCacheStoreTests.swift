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

import Domain
import Testing

@testable import SQLiteDataStore

@Suite("GRDBWallpaperCacheStore")
struct GRDBWallpaperCacheStoreTests {
    private func makeStore() throws -> GRDBWallpaperCacheStore {
        GRDBWallpaperCacheStore(dbManager: try DatabaseManager(inMemory: true))
    }

    @Test("read returns nil for unknown URL")
    func readReturnsNilForUnknown() async throws {
        let store = try makeStore()
        let result = await store.read(url: "https://example.com/video.mp4")
        #expect(result == nil)
    }

    @Test("write then read returns stored entry")
    func writeAndReadRoundTrip() async throws {
        let store = try makeStore()
        try await store.write(url: "https://example.com/video.mp4", contentHash: "abc123", fileExt: "mp4")
        let entry = await store.read(url: "https://example.com/video.mp4")
        #expect(entry?.contentHash == "abc123")
        #expect(entry?.fileExt == "mp4")
    }

    @Test("same URL overwrites previous entry")
    func sameURLOverwrites() async throws {
        let store = try makeStore()
        try await store.write(url: "https://example.com/v.mp4", contentHash: "hash1", fileExt: "mp4")
        try await store.write(url: "https://example.com/v.mp4", contentHash: "hash2", fileExt: "mp4")
        let entry = await store.read(url: "https://example.com/v.mp4")
        #expect(entry?.contentHash == "hash2")
    }

    @Test("two URLs can share same content hash (deduplication)")
    func twoURLsSameContentHash() async throws {
        let store = try makeStore()
        try await store.write(url: "https://a.com/v.mp4", contentHash: "shared_hash", fileExt: "mp4")
        try await store.write(url: "https://b.com/v.mp4", contentHash: "shared_hash", fileExt: "mp4")
        let entryA = await store.read(url: "https://a.com/v.mp4")
        let entryB = await store.read(url: "https://b.com/v.mp4")
        #expect(entryA?.contentHash == entryB?.contentHash)
    }
}