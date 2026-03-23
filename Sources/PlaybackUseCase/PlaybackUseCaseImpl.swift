import Domain
import Dependencies

public struct PlaybackUseCaseImpl {
    @Dependency(\.nowPlayingRepository) private var nowPlaying

    public init() {}
}

extension PlaybackUseCaseImpl: PlaybackUseCase {
    public func observeNowPlaying() -> AsyncStream<NowPlaying?> {
        nowPlaying.stream()
    }
}

extension PlaybackUseCaseKey: DependencyKey {
    public static let liveValue: any PlaybackUseCase = PlaybackUseCaseImpl()
}
