import Dependencies

public protocol LyricsRepository: Sendable {
    func fetchLyrics(track: Track) async -> LyricsResult?
    func fetchLyrics(candidates: [Track]) async -> LyricsResult?
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
    func fetchLyrics(track: Track) async -> LyricsResult? { nil }
    func fetchLyrics(candidates: [Track]) async -> LyricsResult? { nil }
}
