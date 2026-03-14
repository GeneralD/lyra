import BackdropDomain
import BackdropMediaRemote
import Dependencies
import Foundation

public struct NowPlayingService: NowPlayingProvider, Sendable {
    private let bridge: MediaRemoteBridge
    private let interval: TimeInterval

    public init(bridge: MediaRemoteBridge, interval: TimeInterval = 1.0) {
        self.bridge = bridge
        self.interval = interval
    }

    public func stream() -> AsyncStream<NowPlaying?> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    let info = await bridge.poll()
                    continuation.yield(info.map(Self.toNowPlaying))
                    try? await Task.sleep(for: .seconds(interval))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func toNowPlaying(_ info: MediaRemoteInfo) -> NowPlaying {
        NowPlaying(
            title: info.title,
            artist: info.artist,
            artworkData: info.artworkData,
            duration: info.duration,
            rawElapsed: info.rawElapsed,
            playbackRate: info.playbackRate,
            timestamp: info.timestamp
        )
    }
}

// MARK: - DependencyKey

extension NowPlayingProviderKey: DependencyKey {
    public static let liveValue: any NowPlayingProvider = {
        guard let bridge = MediaRemoteBridge() else {
            return NoopNowPlayingProvider()
        }
        return NowPlayingService(bridge: bridge)
    }()
}

private struct NoopNowPlayingProvider: NowPlayingProvider {
    func stream() -> AsyncStream<NowPlaying?> {
        AsyncStream { $0.finish() }
    }
}
