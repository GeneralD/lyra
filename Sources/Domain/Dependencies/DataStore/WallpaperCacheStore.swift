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
