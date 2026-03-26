import Dependencies

public protocol TrackInteractor: Sendable {
    func observeTrack() -> AsyncStream<TrackUpdate>
    var decodeEffectConfig: DecodeEffect { get }
    var textLayout: TextLayout { get }
    var artworkStyle: ArtworkStyle { get }
}

public enum TrackInteractorKey: TestDependencyKey {
    public static let testValue: any TrackInteractor = UnimplementedTrackInteractor()
}

extension DependencyValues {
    public var trackInteractor: any TrackInteractor {
        get { self[TrackInteractorKey.self] }
        set { self[TrackInteractorKey.self] = newValue }
    }
}

private struct UnimplementedTrackInteractor: TrackInteractor {
    func observeTrack() -> AsyncStream<TrackUpdate> {
        AsyncStream { $0.finish() }
    }
    var decodeEffectConfig: DecodeEffect { .init() }
    var textLayout: TextLayout { .init() }
    var artworkStyle: ArtworkStyle { .init() }
}
