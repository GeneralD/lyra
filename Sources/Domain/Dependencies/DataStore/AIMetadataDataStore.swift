import Dependencies

public protocol AIMetadataDataStore: Sendable {
    func read(rawTitle: String, rawArtist: String) async -> Track?
    func write(rawTitle: String, rawArtist: String, candidate: Track) async throws
}

public enum AIMetadataDataStoreKey: TestDependencyKey {
    public static let testValue: any AIMetadataDataStore = NoopAIMetadataCache()
}

extension DependencyValues {
    public var aiMetadataCache: any AIMetadataDataStore {
        get { self[AIMetadataDataStoreKey.self] }
        set { self[AIMetadataDataStoreKey.self] = newValue }
    }
}

private struct NoopAIMetadataCache: AIMetadataDataStore {
    func read(rawTitle: String, rawArtist: String) async -> Track? { nil }
    func write(rawTitle: String, rawArtist: String, candidate: Track) async throws {}
}
