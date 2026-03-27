import Dependencies
import Domain
import Foundation

public struct WallpaperInteractorImpl {
    @Dependency(\.configUseCase) private var configService
    @Dependency(\.wallpaperUseCase) private var wallpaperService

    public init() {}
}

extension WallpaperInteractorImpl: WallpaperInteractor {
    public func resolveWallpaper() async throws -> WallpaperState {
        let appStyle = configService.appStyle
        guard let wallpaper = appStyle.wallpaper else {
            return WallpaperState()
        }
        let configDir = appStyle.configDir ?? FileManager.default.homeDirectoryForCurrentUser.path
        let url = try await wallpaperService.resolveWallpaper(
            value: wallpaper.location, configDir: configDir
        )
        return WallpaperState(url: url, start: wallpaper.start, end: wallpaper.end)
    }

    public var rippleConfig: RippleStyle {
        configService.appStyle.ripple
    }
}
