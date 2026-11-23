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
    public static let liveValue: any MetadataDataSource<Track> = LLMMetadataDataSourceImpl(
        sessionFactory: { config in
            ScopedAPISession(timeout: 60) {
                OpenAICompatibleAPI.api(for: config, urlSession: $0)
            }
        })
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
        // Per-call ephemeral session like every other network path (#318) —
        // timeoutIntervalForRequest bounds idle gaps, not total download time.
        try await ScopedAPISession<URLSession>(timeout: 60) { $0 }
            .withAPI { try await $0.download(from: url) }
    }
}

extension YouTubeWallpaperDataSourceKey: DependencyKey {
    public static let liveValue: any WallpaperDataSource<YouTubeWallpaper> = YouTubeWallpaperDataSourceImpl()
}
