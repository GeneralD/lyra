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

import Dependencies
import Domain
import SQLiteDataStore

private enum SharedDatabaseManager {
    static let instance: DatabaseManager? = try? DatabaseManager()
}

extension LLMMetadataDataStoreKey: DependencyKey {
    public static let liveValue: any MetadataDataStore<Track> = {
        guard let db = SharedDatabaseManager.instance else { return NoopCache() }
        return GRDBLLMMetadataDataStore(dbManager: db)
    }()
}

extension LyricsDataStoreKey: DependencyKey {
    public static let liveValue: any LyricsDataStore = {
        guard let db = SharedDatabaseManager.instance else { return NoopLyricsDataStore() }
        return GRDBLyricsDataStore(dbManager: db)
    }()
}

extension MusicBrainzMetadataDataStoreKey: DependencyKey {
    public static let liveValue: any MetadataDataStore<MusicBrainzMetadata> = {
        guard let db = SharedDatabaseManager.instance else { return NoopCache() }
        return GRDBMetadataDataStore(dbManager: db)
    }()
}

extension WallpaperCacheStoreKey: DependencyKey {
    public static let liveValue: any WallpaperCacheStore = {
        guard let db = SharedDatabaseManager.instance else { return NoopWallpaperCache() }
        return GRDBWallpaperCacheStore(dbManager: db)
    }()
}

// MARK: - Noop fallbacks

private struct NoopCache<Value: Sendable>: MetadataDataStore {
    func read(title: String, artist: String) async -> Value? { nil }
    func write(title: String, artist: String, value: Value) async throws {}
}

private struct NoopLyricsDataStore: LyricsDataStore {
    func read(title: String, artist: String) async -> LyricsResult? { nil }
    func write(title: String, artist: String, result: LyricsResult) async throws {}
}

private struct NoopWallpaperCache: WallpaperCacheStore {
    func read(url: String) async -> WallpaperCacheEntry? { nil }
    func write(url: String, contentHash: String, fileExt: String) async throws {}
}