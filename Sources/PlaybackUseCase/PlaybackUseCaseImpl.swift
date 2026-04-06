import Dependencies
import Domain
import Foundation

public struct PlaybackUseCaseImpl {
    @Dependency(\.nowPlayingRepository) private var nowPlaying
    @Dependency(\.date.now) private var now

    public init() {}
}

extension PlaybackUseCaseImpl: PlaybackUseCase {
    public func fetchNowPlaying() async -> NowPlaying? {
        await nowPlaying.fetch()
    }

    public func observeNowPlaying() -> AsyncStream<NowPlaying?> {
        nowPlaying.stream()
    }

    public func elapsedTime(for nowPlaying: NowPlaying) -> TimeInterval? {
        guard let base = nowPlaying.rawElapsed else { return nil }
        guard let ts = nowPlaying.timestamp else { return base }
        return base + nowPlaying.playbackRate * now.timeIntervalSince(ts)
    }
}
