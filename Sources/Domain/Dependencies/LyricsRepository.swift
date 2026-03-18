import Dependencies
import Foundation

public protocol LyricsRepository: Sendable {
    func fetch(
        title: String, artist: String, duration: TimeInterval?,
        onMetadataResolved: @MainActor @Sendable (SearchCandidate) -> Void
    ) async -> LyricsResult?
}

extension LyricsRepository {
    public func fetch(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? {
        await fetch(title: title, artist: artist, duration: duration, onMetadataResolved: { _ in })
    }
}

public enum LyricsRepositoryKey: TestDependencyKey {
    public static let testValue: any LyricsRepository = UnimplementedLyricsRepository()
}

extension DependencyValues {
    public var lyricsRepository: any LyricsRepository {
        get { self[LyricsRepositoryKey.self] }
        set { self[LyricsRepositoryKey.self] = newValue }
    }
}

private struct UnimplementedLyricsRepository: LyricsRepository {
    func fetch(title: String, artist: String, duration: TimeInterval?, onMetadataResolved: @MainActor @Sendable (SearchCandidate) -> Void) async -> LyricsResult? {
        nil
    }
}
