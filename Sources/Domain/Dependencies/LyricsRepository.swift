import Dependencies
import Foundation

public protocol LyricsRepository: Sendable {
    func fetchLyrics(track: Track, duration: TimeInterval?) async -> LyricsResult?
    func fetchLyrics(candidates: [Track], duration: TimeInterval?) async -> LyricsResult?
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
    func fetchLyrics(track: Track, duration: TimeInterval?) async -> LyricsResult? { nil }
    func fetchLyrics(candidates: [Track], duration: TimeInterval?) async -> LyricsResult? { nil }
}
