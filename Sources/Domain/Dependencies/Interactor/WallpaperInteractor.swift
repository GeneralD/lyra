import Dependencies
import Foundation

public protocol WallpaperInteractor: Sendable {
    func resolveWallpaper() async throws -> WallpaperState
    var rippleConfig: RippleStyle { get }
}

public enum WallpaperInteractorKey: TestDependencyKey {
    public static let testValue: any WallpaperInteractor = UnimplementedWallpaperInteractor()
}

extension DependencyValues {
    public var wallpaperInteractor: any WallpaperInteractor {
        get { self[WallpaperInteractorKey.self] }
        set { self[WallpaperInteractorKey.self] = newValue }
    }
}

private struct UnimplementedWallpaperInteractor: WallpaperInteractor {
    func resolveWallpaper() async throws -> WallpaperState {
        WallpaperState()
    }
    var rippleConfig: RippleStyle { .init() }
}
