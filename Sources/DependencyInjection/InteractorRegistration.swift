import AppKitScreenProvider
import ConfigInteractor
import Dependencies
import Domain
import ScreenInteractor
import SpectrumInteractor
import TrackInteractor
import WallpaperInteractor

extension TrackInteractorKey: DependencyKey {
    public static let liveValue: any TrackInteractor = TrackInteractorImpl()
}

extension ScreenInteractorKey: DependencyKey {
    public static let liveValue: any ScreenInteractor = ScreenInteractorImpl()
}

extension ConfigInteractorKey: DependencyKey {
    public static let liveValue: any ConfigInteractor = ConfigInteractorImpl()
}

extension WallpaperInteractorKey: DependencyKey {
    public static let liveValue: any WallpaperInteractor = WallpaperInteractorImpl()
}

extension SpectrumInteractorKey: DependencyKey {
    public static let liveValue: any SpectrumInteractor = SpectrumInteractorImpl()
}

extension ScreenProviderKey: DependencyKey {
    public static let liveValue: any ScreenProvider = AppKitScreenProvider()
}
