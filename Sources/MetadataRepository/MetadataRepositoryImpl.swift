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
        return dedupedByIdentity(llmCandidates + mbCandidates + regexCandidates + [track])
    }

    public func isAIMetadataCached(track: Track) async -> Bool {
        await llmDataStore.read(title: track.title, artist: track.artist) != nil
    }
}

// MARK: - Private

extension MetadataRepositoryImpl {
    // Collapse duplicate candidates, keeping the first occurrence so the LLM >
    // MusicBrainz > Regex > raw precedence is preserved. Identical guesses from
    // different sources (e.g. raw == a regex candidate) otherwise cost the downstream
    // lyrics tiers redundant network lookups and custom-script spawns. Duration is part
    // of the identity: LRCLIB exact matching and LyricsMatchValidator both discriminate
    // on it, so two same-named MusicBrainz recordings with different durations are
    // genuinely distinct candidates that must both survive.
    private struct CandidateIdentity: Hashable {
        let title: String
        let artist: String
        let duration: Double?
    }

    private func dedupedByIdentity(_ tracks: [Track]) -> [Track] {
        tracks.reduce(into: (seen: Set<CandidateIdentity>(), result: [Track]())) { acc, track in
            let key = CandidateIdentity(
                title: track.title.lowercased(), artist: track.artist.lowercased(), duration: track.duration)
            guard acc.seen.insert(key).inserted else { return }
            acc.result.append(track)
        }.result
    }

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
        // Cache ALL candidate recordings, not just the first: the lyrics flow can cache
        // a hit under any of them, and a cache hit that returned a truncated candidate
        // set would make that lyrics entry unreachable on subsequent plays.
        if let cached = await musicBrainzDataStore.read(title: track.title, artist: track.artist) {
            return cached.map { Track(title: $0.title, artist: $0.artist, duration: $0.duration) }
        }
        let candidates = await musicBrainzDataSource.resolve(track: track)
        if !candidates.isEmpty {
            try? await musicBrainzDataStore.write(title: track.title, artist: track.artist, value: candidates)
        }
        return candidates.map { Track(title: $0.title, artist: $0.artist, duration: $0.duration) }
    }
}
