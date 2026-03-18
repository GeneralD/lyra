import Domain
import Dependencies
import Foundation

public struct LyricsService {
    @Dependency(\.lyricsRepository) private var repository

    public init() {}

    public func fetch(
        title: String, artist: String, duration: TimeInterval?,
        onMetadataResolved: @MainActor @Sendable (SearchCandidate) -> Void = { _ in }
    ) async -> LyricsResult {
        await repository.fetch(title: title, artist: artist, duration: duration, onMetadataResolved: onMetadataResolved) ?? .empty
    }
}

extension LyricsService: Sendable {}
