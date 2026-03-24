import Dependencies
import Domain

public struct PlaybackUseCaseImpl {
    @Dependency(\.nowPlayingRepository) private var nowPlaying

    public init() {}
}

extension PlaybackUseCaseImpl: PlaybackUseCase {
    public func observeNowPlaying() -> AsyncStream<NowPlaying?> {
        nowPlaying.stream()
    }
}
