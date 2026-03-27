import Dependencies
import Foundation

public protocol NowPlayingRepository: Sendable {
    func stream() -> AsyncStream<NowPlaying?>
}

public enum NowPlayingRepositoryKey: TestDependencyKey {
    public static let testValue: any NowPlayingRepository = UnimplementedNowPlayingRepository()
}

extension DependencyValues {
    public var nowPlayingRepository: any NowPlayingRepository {
        get { self[NowPlayingRepositoryKey.self] }
        set { self[NowPlayingRepositoryKey.self] = newValue }
    }
}

private struct UnimplementedNowPlayingRepository: NowPlayingRepository {
    func stream() -> AsyncStream<NowPlaying?> {
        AsyncStream { $0.finish() }
    }
}
