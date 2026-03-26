import Dependencies
import Domain
import ScreenInteractor
import TrackInteractor
import WallpaperInteractor

extension TrackInteractorKey: DependencyKey {
    public static let liveValue: any TrackInteractor = TrackInteractorImpl()
}

extension ScreenInteractorKey: DependencyKey {
    public static let liveValue: any ScreenInteractor = ScreenInteractorImpl()
}

extension WallpaperInteractorKey: DependencyKey {
    public static let liveValue: any WallpaperInteractor = WallpaperInteractorImpl()
}
