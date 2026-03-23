import Domain
import Dependencies

public struct LyricsService: Sendable {
    @Dependency(\.lyricsRepository) private var repository

    public init() {}

    public func fetchLyrics(track: Track) async -> LyricsResult {
        await repository.fetchLyrics(track: track) ?? .empty
    }

    public func fetchLyrics(candidates: [Track]) async -> LyricsResult {
        await repository.fetchLyrics(candidates: candidates) ?? .empty
    }
}
