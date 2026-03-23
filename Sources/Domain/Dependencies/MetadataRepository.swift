import Dependencies

public protocol MetadataRepository: Sendable {
    func resolve(track: Track) async -> [Track]
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
}
