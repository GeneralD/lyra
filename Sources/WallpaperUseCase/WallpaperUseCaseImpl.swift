import Dependencies
import Domain
import Foundation

public struct WallpaperUseCaseImpl: Sendable {
    @Dependency(\.wallpaperRepository) private var repository

    public init() {}
}

extension WallpaperUseCaseImpl: WallpaperUseCase {
    public func resolveWallpaper(value: String?, configDir: String) async throws -> URL? {
        try await repository.resolve(value: value, configDir: configDir)
    }
}
