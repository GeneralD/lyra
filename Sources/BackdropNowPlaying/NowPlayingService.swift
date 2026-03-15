import BackdropDomain
import BackdropMediaRemote
import Dependencies
import Foundation

public struct NowPlayingService: NowPlayingProvider {
    private let bridge: MediaRemoteBridge

    public init(bridge: MediaRemoteBridge) {
        self.bridge = bridge
    }
}

extension NowPlayingService {
    public func stream() -> AsyncStream<NowPlaying?> {
        let bridge = self.bridge
        return AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    switch await bridge.poll() {
                    case .info(let info):
                        continuation.yield(NowPlaying(from: info))
                    case .noInfo:
                        continuation.yield(nil)
                    case .eof:
                        continuation.finish()
                        return
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

extension NowPlaying {
    init(from info: MediaRemoteInfo) {
        self.init(
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
    public static let liveValue: any NowPlayingProvider = NowPlayingService(bridge: MediaRemoteBridge())
}

extension NowPlayingService: Sendable {}
