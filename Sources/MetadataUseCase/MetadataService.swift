import Domain
import Dependencies

public struct MetadataService: Sendable {
    @Dependency(\.metadataRepository) private var repository

    public init() {}

    public func resolve(track: Track) async -> Track? {
        let candidates = await repository.resolve(track: track)
        return candidates.first
    }

    public func resolveCandidates(track: Track) async -> [Track] {
        await repository.resolve(track: track)
    }
}
