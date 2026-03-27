import Dependencies
import Foundation

public protocol WallpaperUseCase: Sendable {
    func resolveWallpaper(value: String?, configDir: String) async throws -> URL?
}

public enum WallpaperUseCaseKey: TestDependencyKey {
    public static let testValue: any WallpaperUseCase = UnimplementedWallpaperUseCase()
}

extension DependencyValues {
    public var wallpaperUseCase: any WallpaperUseCase {
        get { self[WallpaperUseCaseKey.self] }
        set { self[WallpaperUseCaseKey.self] = newValue }
    }
}

private struct UnimplementedWallpaperUseCase: WallpaperUseCase {
    func resolveWallpaper(value: String?, configDir: String) async throws -> URL? { nil }
}
