import ConfigDataSource
import Dependencies
import Domain
import LyricsDataSource
import MediaRemoteDataSource
import MetadataDataSource
import WallpaperDataSource

extension ConfigDataSourceKey: DependencyKey {
    public static let liveValue: any ConfigDataSource = ConfigDataSourceImpl()
}

extension LyricsDataSourceKey: DependencyKey {
    public static let liveValue: any LyricsDataSource = LyricsDataSourceImpl()
}

extension MediaRemoteDataSourceKey: DependencyKey {
    public static let liveValue: any MediaRemoteDataSource = MediaRemoteBridge()
}

extension LLMMetadataDataSourceKey: DependencyKey {
    public static let liveValue: any MetadataDataSource<Track> = LLMMetadataDataSourceImpl()
}

extension MusicBrainzMetadataDataSourceKey: DependencyKey {
    public static let liveValue: any MetadataDataSource<MusicBrainzMetadata> = MusicBrainzMetadataDataSourceImpl()
}

extension RegexMetadataDataSourceKey: DependencyKey {
    public static let liveValue: any MetadataDataSource<Track> = RegexMetadataDataSourceImpl()
}

extension LocalWallpaperDataSourceKey: DependencyKey {
    public static let liveValue: any WallpaperDataSource<LocalWallpaper> = LocalWallpaperDataSourceImpl()
}

extension RemoteWallpaperDataSourceKey: DependencyKey {
    public static let liveValue: any WallpaperDataSource<RemoteWallpaper> = RemoteWallpaperDataSourceImpl()
}

extension YouTubeWallpaperDataSourceKey: DependencyKey {
    public static let liveValue: any WallpaperDataSource<YouTubeWallpaper> = YouTubeWallpaperDataSourceImpl()
}
