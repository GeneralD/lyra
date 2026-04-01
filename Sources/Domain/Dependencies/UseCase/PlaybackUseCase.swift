import Dependencies
import Foundation

public protocol PlaybackUseCase: Sendable {
    func fetchNowPlaying() async -> NowPlaying?
    func observeNowPlaying() -> AsyncStream<NowPlaying?>
}

public enum PlaybackUseCaseKey: TestDependencyKey {
    public static let testValue: any PlaybackUseCase = UnimplementedPlaybackUseCase()
}

extension DependencyValues {
    public var playbackUseCase: any PlaybackUseCase {
        get { self[PlaybackUseCaseKey.self] }
        set { self[PlaybackUseCaseKey.self] = newValue }
    }
}

private struct UnimplementedPlaybackUseCase: PlaybackUseCase {
    func fetchNowPlaying() async -> NowPlaying? { nil }
    func observeNowPlaying() -> AsyncStream<NowPlaying?> { AsyncStream { $0.finish() } }
}
