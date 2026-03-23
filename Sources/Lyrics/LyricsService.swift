import Domain
import Dependencies
import Foundation

public struct LyricsService: Sendable {
    @Dependency(\.lyricsRepository) private var lyricsRepository
    @Dependency(\.metadataRepository) private var metadataRepository

    public init() {}

    public func resolveMetadata(title: String, artist: String) async -> Track? {
        let candidates = await metadataRepository.resolve(track: Track(title: title, artist: artist))
        return candidates.first
    }

    public func fetchLyrics(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult {
        let rawTrack = Track(title: title, artist: artist)
        let candidates = await metadataRepository.resolve(track: rawTrack)

        guard !candidates.isEmpty else {
            return await lyricsRepository.fetchLyrics(track: rawTrack, duration: duration) ?? .empty
        }

        return await lyricsRepository.fetchLyrics(candidates: candidates, duration: duration) ?? .empty
    }
}
