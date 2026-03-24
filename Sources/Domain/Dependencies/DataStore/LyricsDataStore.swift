import Dependencies

public protocol LyricsDataStore: Sendable {
    func read(title: String, artist: String) async -> LyricsResult?
    func write(title: String, artist: String, result: LyricsResult) async throws
}

public enum LyricsDataStoreKey: TestDependencyKey {
    public static let testValue: any LyricsDataStore = UnimplementedLyricsDataStore()
}

extension DependencyValues {
    public var lyricsCache: any LyricsDataStore {
        get { self[LyricsDataStoreKey.self] }
        set { self[LyricsDataStoreKey.self] = newValue }
    }
}

private struct UnimplementedLyricsDataStore: LyricsDataStore {
    func read(title: String, artist: String) async -> LyricsResult? { nil }
    func write(title: String, artist: String, result: LyricsResult) async throws {}
}
