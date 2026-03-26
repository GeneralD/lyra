import Combine
import Dependencies

public protocol TrackInteractor: Sendable {
    var track: AnyPublisher<TrackUpdate, Never> { get }
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
    var track: AnyPublisher<TrackUpdate, Never> {
        Empty().eraseToAnyPublisher()
    }
    var decodeEffectConfig: DecodeEffect { .init() }
    var textLayout: TextLayout { .init() }
    var artworkStyle: ArtworkStyle { .init() }
}
