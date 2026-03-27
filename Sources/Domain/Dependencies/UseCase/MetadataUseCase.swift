import Dependencies

public protocol MetadataUseCase: Sendable {
    func resolve(track: Track) async -> Track?
    func resolveCandidates(track: Track) async -> [Track]
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
}
