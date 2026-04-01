import Dependencies
import Domain

public struct PlaybackUseCaseImpl {
    @Dependency(\.nowPlayingRepository) private var nowPlaying

    public init() {}
}

extension PlaybackUseCaseImpl: PlaybackUseCase {
    public func fetchNowPlaying() async -> NowPlaying? {
        await nowPlaying.fetch()
    }

    public func observeNowPlaying() -> AsyncStream<NowPlaying?> {
        nowPlaying.stream()
    }
}
