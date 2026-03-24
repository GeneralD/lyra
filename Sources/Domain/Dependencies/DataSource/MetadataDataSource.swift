import Dependencies

public protocol MetadataDataSource<Value>: Sendable {
    associatedtype Value: Sendable
    func resolve(track: Track) async -> [Value]
}

// MARK: - LLM (Track)

public enum LLMMetadataDataSourceKey: TestDependencyKey {
    public static let testValue: any MetadataDataSource<Track> = NoopMetadataDataSource()
}

extension DependencyValues {
    public var llmMetadataDataSource: any MetadataDataSource<Track> {
        get { self[LLMMetadataDataSourceKey.self] }

        set { self[LLMMetadataDataSourceKey.self] = newValue }
    }
}

// MARK: - MusicBrainz (MusicBrainzMetadata)

public enum MusicBrainzMetadataDataSourceKey: TestDependencyKey {
    public static let testValue: any MetadataDataSource<MusicBrainzMetadata> = NoopMetadataDataSource()
}

extension DependencyValues {
    public var musicBrainzMetadataDataSource: any MetadataDataSource<MusicBrainzMetadata> {
        get { self[MusicBrainzMetadataDataSourceKey.self] }
        set { self[MusicBrainzMetadataDataSourceKey.self] = newValue }
    }
}

// MARK: - Regex (Track)

public enum RegexMetadataDataSourceKey: TestDependencyKey {
    public static let testValue: any MetadataDataSource<Track> = NoopMetadataDataSource()
}

extension DependencyValues {
    public var regexMetadataDataSource: any MetadataDataSource<Track> {
        get { self[RegexMetadataDataSourceKey.self] }
        set { self[RegexMetadataDataSourceKey.self] = newValue }
    }
}

// MARK: - Noop

private struct NoopMetadataDataSource<Value: Sendable>: MetadataDataSource {
    func resolve(track: Track) async -> [Value] { [] }
}
