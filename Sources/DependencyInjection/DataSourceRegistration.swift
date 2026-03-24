import ConfigDataSource
import Dependencies
import Domain
import LyricsDataSource
import MediaRemoteDataSource
import MetadataDataSource

extension ConfigDataSourceKey: DependencyKey {
    public static let liveValue: any ConfigDataSource = ConfigDataSourceImpl()
}

extension LyricsDataSourceKey: DependencyKey {
    public static let liveValue: any LyricsDataSource = LyricsDataSourceImpl()
}

extension MediaRemoteDataSourceKey: DependencyKey {
    public static let liveValue: any MediaRemoteDataSource = MediaRemoteBridge()
}

extension MetadataDataSourceKey: DependencyKey {
    public static let liveValue: [any MetadataDataSource] = [
        LLMMetadataDataSourceImpl(),
        MusicBrainzMetadataDataSourceImpl(),
    ]
}
