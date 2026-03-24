import Dependencies
import Domain

public struct MetadataRepositoryImpl {
    @Dependency(\.metadataDataSources) private var dataSources

    public init() {}
}

extension MetadataRepositoryImpl: MetadataRepository {
    public func resolve(track: Track) async -> [Track] {
        for dataSource in dataSources {
            let candidates = await dataSource.resolve(track: track)
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
