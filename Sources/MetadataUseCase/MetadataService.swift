import Domain
import Dependencies

public struct MetadataService: Sendable {
    @Dependency(\.metadataRepository) private var repository

    public init() {}

    public func resolve(title: String, artist: String) async -> Track? {
        let candidates = await repository.resolve(track: Track(title: title, artist: artist))
        return candidates.first
    }

    public func resolveCandidates(title: String, artist: String) async -> [Track] {
        await repository.resolve(track: Track(title: title, artist: artist))
    }
}
