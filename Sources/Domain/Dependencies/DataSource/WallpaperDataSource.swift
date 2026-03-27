import Dependencies

public protocol WallpaperDataSource<LocationType>: Sendable {
    associatedtype LocationType: Sendable
    func resolve(_ location: LocationType) async throws -> String
}

// MARK: - Local

public enum LocalWallpaperDataSourceKey: TestDependencyKey {
    public static let testValue: any WallpaperDataSource<LocalWallpaper> = NoopWallpaperDataSource()
}

extension DependencyValues {
    public var localWallpaperDataSource: any WallpaperDataSource<LocalWallpaper> {
        get { self[LocalWallpaperDataSourceKey.self] }
        set { self[LocalWallpaperDataSourceKey.self] = newValue }
    }
}

// MARK: - Remote

public enum RemoteWallpaperDataSourceKey: TestDependencyKey {
    public static let testValue: any WallpaperDataSource<RemoteWallpaper> = NoopWallpaperDataSource()
}

extension DependencyValues {
    public var remoteWallpaperDataSource: any WallpaperDataSource<RemoteWallpaper> {
        get { self[RemoteWallpaperDataSourceKey.self] }
        set { self[RemoteWallpaperDataSourceKey.self] = newValue }
    }
}

// MARK: - YouTube

public enum YouTubeWallpaperDataSourceKey: TestDependencyKey {
    public static let testValue: any WallpaperDataSource<YouTubeWallpaper> = NoopWallpaperDataSource()
}

extension DependencyValues {
    public var youtubeWallpaperDataSource: any WallpaperDataSource<YouTubeWallpaper> {
        get { self[YouTubeWallpaperDataSourceKey.self] }
        set { self[YouTubeWallpaperDataSourceKey.self] = newValue }
    }
}

// MARK: - Noop

private struct NoopWallpaperDataSource<L: Sendable>: WallpaperDataSource {
    func resolve(_ location: L) async throws -> String { "" }
}
