import Dependencies
import Foundation

public protocol WallpaperRepository: Sendable {
    /// Classify wallpaper value and resolve to a local file URL.
    /// Returns nil if the value is nil or empty.
    func resolve(value: String?, configDir: String) async throws -> URL?
}

public enum WallpaperRepositoryKey: TestDependencyKey {
    public static let testValue: any WallpaperRepository = UnimplementedWallpaperRepository()
}

extension DependencyValues {
    public var wallpaperRepository: any WallpaperRepository {
        get { self[WallpaperRepositoryKey.self] }
        set { self[WallpaperRepositoryKey.self] = newValue }
    }
}

private struct UnimplementedWallpaperRepository: WallpaperRepository {
    func resolve(value: String?, configDir: String) async throws -> URL? { nil }
}
