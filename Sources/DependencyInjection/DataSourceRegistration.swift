import AudioTapDataSource
import ConfigDataSource
import Dependencies
import Domain
import Foundation
import LyricsDataSource
import MediaRemoteDataSource
import MetadataDataSource
@preconcurrency import Papyrus
import ScopedAPISession
import WallpaperDataSource

extension AudioTapDataSourceKey: DependencyKey {
    public static let liveValue: any AudioTapDataSource = AudioTapDataSourceImpl()
}

extension ConfigDataSourceKey: DependencyKey {
    public static let liveValue: any ConfigDataSource = ConfigDataSourceImpl()
}

extension LyricsDataSourceKey: DependencyKey {
    public static let liveValue: any LyricsDataSource = LyricsDataSourceImpl(
        apiSession: ScopedAPISession(timeout: 10) {
            LRCLibAPI(provider: Provider(baseURL: LRCLibAPI.baseURL, urlSession: $0))
        }
    )
}

extension CustomScriptLyricsDataSourceKey: DependencyKey {
    public static let liveValue: any LyricsDataSource = CustomScriptLyricsDataSourceImpl()
}

extension MediaRemoteDataSourceKey: DependencyKey {
    public static let liveValue: any MediaRemoteDataSource = MediaRemoteDataSourceImpl()
}

extension LLMMetadataDataSourceKey: DependencyKey {
    public static let liveValue: any MetadataDataSource<Track> = LLMMetadataDataSourceImpl()
}

extension MusicBrainzMetadataDataSourceKey: DependencyKey {
    public static let liveValue: any MetadataDataSource<MusicBrainzMetadata> = MusicBrainzMetadataDataSourceImpl(
        apiSession: ScopedAPISession(timeout: 10) {
            MusicBrainzAPI(provider: Provider(baseURL: MusicBrainzAPI.baseURL, urlSession: $0))
        }
    )
}

extension RegexMetadataDataSourceKey: DependencyKey {
    public static let liveValue: any MetadataDataSource<Track> = RegexMetadataDataSourceImpl()
}

extension LocalWallpaperDataSourceKey: DependencyKey {
    public static let liveValue: any WallpaperDataSource<LocalWallpaper> = LocalWallpaperDataSourceImpl()
}

extension RemoteWallpaperDataSourceKey: DependencyKey {
    public static let liveValue: any WallpaperDataSource<RemoteWallpaper> = RemoteWallpaperDataSourceImpl { url in
        try await URLSession.shared.download(from: url)
    }
}

extension YouTubeWallpaperDataSourceKey: DependencyKey {
    public static let liveValue: any WallpaperDataSource<YouTubeWallpaper> = YouTubeWallpaperDataSourceImpl()
}
