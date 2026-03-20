import Domain
import Dependencies
import Foundation

public struct LyricsService {
    @Dependency(\.lyricsRepository) private var repository

    public init() {}

    public func resolveMetadata(title: String, artist: String) async -> Track? {
        await repository.resolveMetadata(title: title, artist: artist)
    }

    public func fetchLyrics(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult {
        await repository.fetchLyrics(title: title, artist: artist, duration: duration) ?? .empty
    }
}

extension LyricsService: Sendable {}
