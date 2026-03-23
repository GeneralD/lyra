import Domain
import Dependencies

public struct MetadataUseCaseImpl {
    @Dependency(\.metadataRepository) private var repository

    public init() {}
}

extension MetadataUseCaseImpl: MetadataUseCase {
    public func resolve(track: Track) async -> Track? {
        let candidates = await repository.resolve(track: track)
        return candidates.first
    }

    public func resolveCandidates(track: Track) async -> [Track] {
        await repository.resolve(track: track)
    }
}

extension MetadataUseCaseKey: DependencyKey {
    public static let liveValue: any MetadataUseCase = MetadataUseCaseImpl()
}
