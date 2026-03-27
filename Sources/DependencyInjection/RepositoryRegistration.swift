import ConfigRepository
import Dependencies
import Domain
import LyricsRepository
import MetadataRepository
import NowPlayingRepository
import WallpaperRepository

extension ConfigRepositoryKey: DependencyKey {
    public static let liveValue: any ConfigRepository = ConfigRepositoryImpl()
}

extension LyricsRepositoryKey: DependencyKey {
    public static let liveValue: any LyricsRepository = LyricsRepositoryImpl()
}

extension MetadataRepositoryKey: DependencyKey {
    public static let liveValue: any MetadataRepository = MetadataRepositoryImpl()
}

extension NowPlayingRepositoryKey: DependencyKey {
    public static let liveValue: any NowPlayingRepository = NowPlayingRepositoryImpl()
}

extension WallpaperRepositoryKey: DependencyKey {
    public static let liveValue: any WallpaperRepository = WallpaperRepositoryImpl()
}
