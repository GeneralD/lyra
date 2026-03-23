import Domain
import Dependencies
import Foundation

public struct LyricsService: Sendable {
    @Dependency(\.lyricsRepository) private var repository
    @Dependency(\.metadataNormalizers) private var normalizers

    public init() {}

    public func resolveMetadata(title: String, artist: String) async -> Track? {
        let rawTrack = Track(title: title, artist: artist)
        for normalizer in normalizers {
            let candidates = await normalizer.resolve(track: rawTrack)
            guard let first = candidates.first else { continue }
            return first
        }
        return nil
    }

    public func fetchLyrics(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult {
        let rawTrack = Track(title: title, artist: artist)

        // Try each normalizer: resolve → fetch with candidates
        for normalizer in normalizers {
            let candidates = await normalizer.resolve(track: rawTrack)
            guard !candidates.isEmpty else { continue }
            if let result = await repository.fetchLyrics(candidates: candidates, duration: duration) {
                return result
            }
        }

        // Last resort: raw track
        return await repository.fetchLyrics(track: rawTrack, duration: duration) ?? .empty
    }
}
