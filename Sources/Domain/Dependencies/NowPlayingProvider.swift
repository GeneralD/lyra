import Dependencies
import DependenciesMacros
import Foundation

public protocol NowPlayingProvider: Sendable {
    func stream() -> AsyncStream<NowPlaying?>
}

public enum NowPlayingProviderKey: TestDependencyKey {
    public static let testValue: any NowPlayingProvider = UnimplementedNowPlayingProvider()
}

extension DependencyValues {
    public var nowPlayingProvider: any NowPlayingProvider {
        get { self[NowPlayingProviderKey.self] }
        set { self[NowPlayingProviderKey.self] = newValue }
    }
}

private struct UnimplementedNowPlayingProvider: NowPlayingProvider {
    func stream() -> AsyncStream<NowPlaying?> {
        AsyncStream { $0.finish() }
    }
}
