import Dependencies
import Domain

public struct MetadataRepositoryImpl: MetadataRepository {
    @Dependency(\.metadataNormalizers) private var normalizers

    public init() {}

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
