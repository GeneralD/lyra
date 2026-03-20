import Dependencies
import Foundation

public struct MusicBrainzMetadata {
    public let title: String
    public let artist: String
    public let duration: TimeInterval?
    public let musicbrainzId: String

    public init(title: String, artist: String, duration: TimeInterval?, musicbrainzId: String) {
        self.title = title
        self.artist = artist
        self.duration = duration
        self.musicbrainzId = musicbrainzId
    }
}

extension MusicBrainzMetadata: Sendable {}

public protocol MetadataCacheRepository: Sendable {
    func read(title: String, artist: String) async -> MusicBrainzMetadata?
    func write(queryTitle: String, queryArtist: String, metadata: MusicBrainzMetadata) async throws
}

public enum MetadataCacheRepositoryKey: TestDependencyKey {
    public static let testValue: any MetadataCacheRepository = NoopMetadataCache()
}

extension DependencyValues {
    public var metadataCache: any MetadataCacheRepository {
        get { self[MetadataCacheRepositoryKey.self] }
        set { self[MetadataCacheRepositoryKey.self] = newValue }
    }
}

private struct NoopMetadataCache: MetadataCacheRepository {
    func read(title: String, artist: String) async -> MusicBrainzMetadata? { nil }
    func write(queryTitle: String, queryArtist: String, metadata: MusicBrainzMetadata) async throws {}
}
