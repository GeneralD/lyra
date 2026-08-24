import Dependencies
import Foundation

public protocol LyricsDataSource: Sendable {
    func get(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult?
    func search(query: String) async -> [LyricsResult]?

    // Structured search on the track name alone. Distinct from `search(query:)` rather
    // than a replacement for it: measured against LRCLIB, the two indexes disagree in
    // both directions — this one ranks clean catalog titles first, but returns nothing
    // for a quarter of the titles the free-text form can still find (#343). Callers are
    // expected to try both. The artist is deliberately not a parameter: as a server-side
    // filter it is a hard cut on a low-confidence field, and agreement is checked locally.
    func search(trackName: String) async -> [LyricsResult]?
}

public enum LyricsDataSourceKey: TestDependencyKey {
    public static let testValue: any LyricsDataSource = UnimplementedLyricsDataSource()
}

public enum CustomScriptLyricsDataSourceKey: TestDependencyKey {
    public static let testValue: any LyricsDataSource = UnimplementedLyricsDataSource()
}

extension DependencyValues {
    public var lyricsDataSource: any LyricsDataSource {
        get { self[LyricsDataSourceKey.self] }
        set { self[LyricsDataSourceKey.self] = newValue }
    }

    public var customScriptLyricsDataSource: any LyricsDataSource {
        get { self[CustomScriptLyricsDataSourceKey.self] }
        set { self[CustomScriptLyricsDataSourceKey.self] = newValue }
    }
}

private struct UnimplementedLyricsDataSource: LyricsDataSource {
    func get(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? { nil }
    func search(query: String) async -> [LyricsResult]? { nil }
    func search(trackName: String) async -> [LyricsResult]? { nil }
}
