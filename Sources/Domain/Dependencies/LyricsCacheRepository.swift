import Dependencies

public protocol LyricsCacheRepository: Sendable {
    func read(title: String, artist: String) async -> LyricsResult?
    func write(title: String, artist: String, result: LyricsResult) async throws
}

public enum LyricsCacheRepositoryKey: TestDependencyKey {
    public static let testValue: any LyricsCacheRepository = UnimplementedLyricsCacheRepository()
}

extension DependencyValues {
    public var lyricsCache: any LyricsCacheRepository {
        get { self[LyricsCacheRepositoryKey.self] }
        set { self[LyricsCacheRepositoryKey.self] = newValue }
    }
}

private struct UnimplementedLyricsCacheRepository: LyricsCacheRepository {
    func read(title: String, artist: String) async -> LyricsResult? { nil }
    func write(title: String, artist: String, result: LyricsResult) async throws {}
}
