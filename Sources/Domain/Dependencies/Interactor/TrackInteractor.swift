import Combine
import Dependencies
import Foundation

public protocol TrackInteractor: Sendable {
    /// Emits once per track change, after metadata + lyrics resolution.
    var trackChange: AnyPublisher<TrackUpdate, Never> { get }
    /// Emits when artwork data changes.
    var artwork: AnyPublisher<Data?, Never> { get }
    /// Emits continuously for playback position updates.
    var playbackPosition: AnyPublisher<PlaybackPosition, Never> { get }
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
    var trackChange: AnyPublisher<TrackUpdate, Never> { Empty().eraseToAnyPublisher() }
    var artwork: AnyPublisher<Data?, Never> { Empty().eraseToAnyPublisher() }
    var playbackPosition: AnyPublisher<PlaybackPosition, Never> { Empty().eraseToAnyPublisher() }
    var decodeEffectConfig: DecodeEffect { .init() }
    var textLayout: TextLayout { .init() }
    var artworkStyle: ArtworkStyle { .init() }
}
