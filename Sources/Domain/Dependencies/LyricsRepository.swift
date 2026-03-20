import Dependencies
import Foundation

public protocol LyricsRepository: Sendable {
    func resolveMetadata(title: String, artist: String) async -> Track?
    func fetchLyrics(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult?
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
    func resolveMetadata(title: String, artist: String) async -> Track? { nil }
    func fetchLyrics(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? { nil }
}
