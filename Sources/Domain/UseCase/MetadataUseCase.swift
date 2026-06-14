import Dependencies

public protocol MetadataUseCase: Sendable {
    func resolve(track: Track) async -> Track?
    func resolveCandidates(track: Track) async -> [Track]
    /// Whether the AI (LLM) extractor already has a cached result for this raw
    /// track. Used to decide whether `resolveCandidates` will make a live API
    /// call worth showing a processing indicator for (#57).
    func isAIMetadataCached(track: Track) async -> Bool
}

public enum MetadataUseCaseKey: TestDependencyKey {
    public static let testValue: any MetadataUseCase = UnimplementedMetadataUseCase()
}

extension DependencyValues {
    public var metadataUseCase: any MetadataUseCase {
        get { self[MetadataUseCaseKey.self] }
        set { self[MetadataUseCaseKey.self] = newValue }
    }
}

private struct UnimplementedMetadataUseCase: MetadataUseCase {
    func resolve(track: Track) async -> Track? { nil }
    func resolveCandidates(track: Track) async -> [Track] { [] }
    func isAIMetadataCached(track: Track) async -> Bool { false }
}
