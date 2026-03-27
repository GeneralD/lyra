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
import Foundation

public protocol WallpaperCacheStore: Sendable {
    func read(url: String) async -> WallpaperCacheEntry?
    func write(url: String, contentHash: String, fileExt: String) async throws
}

public struct WallpaperCacheEntry: Sendable {
    public let contentHash: String
    public let fileExt: String

    public init(contentHash: String, fileExt: String) {
        self.contentHash = contentHash
        self.fileExt = fileExt
    }
}

public enum WallpaperCacheStoreKey: TestDependencyKey {
    public static let testValue: any WallpaperCacheStore = NoopWallpaperCacheStore()
}

extension DependencyValues {
    public var wallpaperCacheStore: any WallpaperCacheStore {
        get { self[WallpaperCacheStoreKey.self] }
        set { self[WallpaperCacheStoreKey.self] = newValue }
    }
}

private struct NoopWallpaperCacheStore: WallpaperCacheStore {
    func read(url: String) async -> WallpaperCacheEntry? { nil }
    func write(url: String, contentHash: String, fileExt: String) async throws {}
}