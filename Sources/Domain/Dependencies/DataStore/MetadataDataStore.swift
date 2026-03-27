import Dependencies

public protocol MetadataDataStore<Value>: Sendable {
    associatedtype Value: Sendable
    func read(title: String, artist: String) async -> Value?
    func write(title: String, artist: String, value: Value) async throws
}

// MARK: - LLM Metadata Cache (Track)

public enum LLMMetadataDataStoreKey: TestDependencyKey {
    public static let testValue: any MetadataDataStore<Track> = NoopMetadataDataStore()
}

extension DependencyValues {
    public var llmMetadataDataStore: any MetadataDataStore<Track> {
        get { self[LLMMetadataDataStoreKey.self] }
        set { self[LLMMetadataDataStoreKey.self] = newValue }
    }
}

// MARK: - MusicBrainz Metadata Cache (MusicBrainzMetadata)

public enum MusicBrainzMetadataDataStoreKey: TestDependencyKey {
    public static let testValue: any MetadataDataStore<MusicBrainzMetadata> = NoopMetadataDataStore()
}

extension DependencyValues {
    public var musicBrainzMetadataDataStore: any MetadataDataStore<MusicBrainzMetadata> {
        get { self[MusicBrainzMetadataDataStoreKey.self] }
        set { self[MusicBrainzMetadataDataStoreKey.self] = newValue }
    }
}

// MARK: - Noop

private struct NoopMetadataDataStore<Value: Sendable>: MetadataDataStore {
    func read(title: String, artist: String) async -> Value? { nil }
    func write(title: String, artist: String, value: Value) async throws {}
}
