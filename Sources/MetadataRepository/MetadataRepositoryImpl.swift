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
        // 1. LLM cache
        if let cached = await llmDataStore.read(title: track.title, artist: track.artist) {
            return [cached]
        }

        // 2. LLM DataSource
        let llmCandidates = await llmDataSource.resolve(track: track)
        if let first = llmCandidates.first {
            try? await llmDataStore.write(title: track.title, artist: track.artist, value: first)
            return llmCandidates
        }

        // 3. MusicBrainz cache
        if let cached = await musicBrainzDataStore.read(title: track.title, artist: track.artist) {
            return [Track(title: cached.title, artist: cached.artist)]
        }

        // 4. MusicBrainz DataSource
        let mbCandidates = await musicBrainzDataSource.resolve(track: track)
        if let first = mbCandidates.first {
            try? await musicBrainzDataStore.write(title: track.title, artist: track.artist, value: first)
            return mbCandidates.map { Track(title: $0.title, artist: $0.artist) }
        }

        // 5. Regex DataSource (no cache)
        return await regexDataSource.resolve(track: track)
    }
}
