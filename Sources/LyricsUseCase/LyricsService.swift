import Domain
import Dependencies
import Foundation

public struct LyricsService: Sendable {
    @Dependency(\.lyricsRepository) private var repository

    public init() {}

    public func fetchLyrics(track: Track, duration: TimeInterval?) async -> LyricsResult {
        await repository.fetchLyrics(track: track, duration: duration) ?? .empty
    }

    public func fetchLyrics(candidates: [Track], duration: TimeInterval?) async -> LyricsResult {
        await repository.fetchLyrics(candidates: candidates, duration: duration) ?? .empty
    }
}
