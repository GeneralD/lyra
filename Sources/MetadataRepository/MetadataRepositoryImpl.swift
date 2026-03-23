import Dependencies
import Domain

public struct MetadataRepositoryImpl {
    @Dependency(\.metadataNormalizers) private var normalizers

    public init() {}
}

extension MetadataRepositoryImpl: MetadataRepository {
    public func resolve(track: Track) async -> [Track] {
        for normalizer in normalizers {
            let candidates = await normalizer.resolve(track: track)
            guard !candidates.isEmpty else { continue }
            return candidates
        }
        return []
    }
}

// MARK: - DependencyKey

extension MetadataRepositoryKey: DependencyKey {
    public static let liveValue: any MetadataRepository = MetadataRepositoryImpl()
}
