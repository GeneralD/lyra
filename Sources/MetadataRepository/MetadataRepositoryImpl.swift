import Dependencies
import Domain

public struct MetadataRepositoryImpl {
    @Dependency(\.llmMetadataDataSource) private var llmDataSource
    @Dependency(\.musicBrainzMetadataDataSource) private var musicBrainzDataSource
    @Dependency(\.regexMetadataDataSource) private var regexDataSource
    @Dependency(\.llmMetadataDataStore) private var llmDataStore
    @Dependency(\.musicBrainzMetadataDataStore) private var musicBrainzDataStore

    public init() {}
}

extension MetadataRepositoryImpl: MetadataRepository {
    public func resolve(track: Track) async -> [Track] {
        let llmCandidates = await resolveLLM(track: track)
        let mbCandidates = await resolveMusicBrainz(track: track)
        let regexCandidates = await regexDataSource.resolve(track: track).map {
            Track(title: $0.title, artist: $0.artist, duration: track.duration)
        }
        return llmCandidates + mbCandidates + regexCandidates + [track]
    }

    public func isAIMetadataCached(track: Track) async -> Bool {
        await llmDataStore.read(title: track.title, artist: track.artist) != nil
    }
}

// MARK: - Private

extension MetadataRepositoryImpl {
    private func resolveLLM(track: Track) async -> [Track] {
        if let cached = await llmDataStore.read(title: track.title, artist: track.artist) {
            return [Track(title: cached.title, artist: cached.artist, duration: track.duration)]
        }
        let candidates = await llmDataSource.resolve(track: track)
        if let first = candidates.first {
            try? await llmDataStore.write(title: track.title, artist: track.artist, value: first)
        }
        return candidates.map { Track(title: $0.title, artist: $0.artist, duration: track.duration) }
    }

    private func resolveMusicBrainz(track: Track) async -> [Track] {
        if let cached = await musicBrainzDataStore.read(title: track.title, artist: track.artist) {
            return [Track(title: cached.title, artist: cached.artist, duration: cached.duration)]
        }
        let candidates = await musicBrainzDataSource.resolve(track: track)
        if let first = candidates.first {
            try? await musicBrainzDataStore.write(title: track.title, artist: track.artist, value: first)
        }
        return candidates.map { Track(title: $0.title, artist: $0.artist, duration: $0.duration) }
    }
}
