import Dependencies
import Foundation

public protocol MetadataDataStore: Sendable {
    func read(title: String, artist: String) async -> MusicBrainzMetadata?
    func write(queryTitle: String, queryArtist: String, metadata: MusicBrainzMetadata) async throws
}

public enum MetadataDataStoreKey: TestDependencyKey {
    public static let testValue: any MetadataDataStore = NoopMetadataCache()
}

extension DependencyValues {
    public var metadataCache: any MetadataDataStore {
        get { self[MetadataDataStoreKey.self] }
        set { self[MetadataDataStoreKey.self] = newValue }
    }
}

private struct NoopMetadataCache: MetadataDataStore {
    func read(title: String, artist: String) async -> MusicBrainzMetadata? { nil }
    func write(queryTitle: String, queryArtist: String, metadata: MusicBrainzMetadata) async throws {}
}
