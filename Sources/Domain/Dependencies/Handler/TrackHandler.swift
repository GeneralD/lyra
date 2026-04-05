import Dependencies

public struct TrackQuery: Sendable {
    public let resolve: Bool
    public let lyrics: Bool

    public init(resolve: Bool = false, lyrics: Bool = false) {
        self.resolve = resolve
        self.lyrics = lyrics
    }
}

public protocol TrackHandler: Sendable {
    func fetchInfo(query: TrackQuery) async -> NowPlayingInfo
}

public enum TrackHandlerKey: TestDependencyKey {
    public static let testValue: any TrackHandler = UnimplementedTrackHandler()
}

extension DependencyValues {
    public var trackHandler: any TrackHandler {
        get { self[TrackHandlerKey.self] }
        set { self[TrackHandlerKey.self] = newValue }
    }
}

private struct UnimplementedTrackHandler: TrackHandler {
    func fetchInfo(query: TrackQuery) async -> NowPlayingInfo {
        fatalError("TrackHandler.fetchInfo not implemented")
    }
}
