import Dependencies

public protocol MetadataRepository: Sendable {
    func resolve(track: Track) async -> [Track]
    /// Whether the AI (LLM) extractor already has a cached result for this raw
    /// track. A `false` here with an AI endpoint configured means `resolve` will
    /// make a live API call, which presenters surface as a processing indicator (#57).
    func isAIMetadataCached(track: Track) async -> Bool
}

public enum MetadataRepositoryKey: TestDependencyKey {
    public static let testValue: any MetadataRepository = UnimplementedMetadataRepository()
}

extension DependencyValues {
    public var metadataRepository: any MetadataRepository {
        get { self[MetadataRepositoryKey.self] }
        set { self[MetadataRepositoryKey.self] = newValue }
    }
}

private struct UnimplementedMetadataRepository: MetadataRepository {
    func resolve(track: Track) async -> [Track] { [] }
    func isAIMetadataCached(track: Track) async -> Bool { false }
}
