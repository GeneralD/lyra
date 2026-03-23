import Dependencies
import Foundation

public protocol LyricsDataSource: Sendable {
    func get(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult?
    func search(query: String) async -> [LyricsResult]?
}

public enum LyricsDataSourceKey: TestDependencyKey {
    public static let testValue: any LyricsDataSource = UnimplementedLyricsDataSource()
}

extension DependencyValues {
    public var lyricsDataSource: any LyricsDataSource {
        get { self[LyricsDataSourceKey.self] }
        set { self[LyricsDataSourceKey.self] = newValue }
    }
}

private struct UnimplementedLyricsDataSource: LyricsDataSource {
    func get(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? { nil }
    func search(query: String) async -> [LyricsResult]? { nil }
}
