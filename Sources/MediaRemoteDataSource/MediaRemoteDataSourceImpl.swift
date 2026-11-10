import Dependencies
import Domain
import Foundation

public final class MediaRemoteDataSourceImpl: @unchecked Sendable {
    @Dependency(\.processGateway) private var gateway

    private let state = StreamStateBox()
    private let selector = NowPlayingClientSelector()
    private let decodeBase64: @Sendable (String) -> Data?

    public convenience init() {
        self.init(decodeBase64: { Data(base64Encoded: $0) })
    }

    init(decodeBase64: @escaping @Sendable (String) -> Data?) {
        self.decodeBase64 = decodeBase64
    }
}

extension MediaRemoteDataSourceImpl: MediaRemoteDataSource {
    public func poll() async -> MediaRemotePollResult {
        let currentIterator: AsyncStream<String>.AsyncIterator
        while true {
            if let nextIterator = takeIterator() {
                currentIterator = nextIterator
                break
            }
            await Task.yield()
        }

        var iterator = currentIterator
        guard let line = await iterator.next() else {
            finishPolling(nextIterator: nil)
            return .eof
        }
        finishPolling(nextIterator: iterator)

        guard let frame = HelperFrame(line: line), let nowPlaying = nowPlaying(following: frame) else {
            return .noInfo
        }
        return .info(nowPlaying)
    }
}

extension MediaRemoteDataSourceImpl {
    private func takeIterator() -> AsyncStream<String>.AsyncIterator? {
        state.lock.lock()
        defer { state.lock.unlock() }

        guard !state.isPolling else { return nil }
        if state.iterator == nil {
            guard
                let sourceURL = Bundle.module.url(
                    forResource: "media-remote-helper", withExtension: "swift")
            else {
                state.isPolling = true
                return AsyncStream<String> { $0.finish() }.makeAsyncIterator()
            }
            // MediaRemote private framework only returns now-playing info when the
            // *host* process is Apple-signed with the matching private entitlement.
            // `/usr/bin/swift` is the Apple-signed xcode_select tool-shim that
            // dispatches into the Xcode / CLT swift interpreter (both Apple-signed).
            // Going through `/usr/bin/env swift` instead would respect $PATH and
            // could pick up a Homebrew / swift.org / asdf toolchain whose binary
            // lacks the Apple-private entitlement — reintroducing the regression
            // this change is meant to fix. Pre-compiling with `swiftc` and
            // executing the ad-hoc-signed output is broken on macOS 26+ for the
            // same reason. See issue #261.
            let stream = gateway.runStreaming(
                executable: "/usr/bin/swift", arguments: [sourceURL.path])
            state.iterator = stream.makeAsyncIterator()
        }
        state.isPolling = true
        let iterator = state.iterator
        state.iterator = nil
        return iterator
    }

    private func finishPolling(nextIterator: AsyncStream<String>.AsyncIterator?) {
        state.lock.lock()
        defer { state.lock.unlock() }
        state.isPolling = false
        state.iterator = nextIterator
    }

    /// Folds one frame into the per-client cover cache and picks the client to
    /// follow (#358). The followed client survives a frame without candidates,
    /// so a momentary gap does not cost the selection its stickiness. Covers are
    /// decoded only when a client's digest changes (#255, #270).
    private func nowPlaying(following frame: HelperFrame) -> NowPlaying? {
        state.lock.lock()
        defer { state.lock.unlock() }
        state.artworkCache = state.artworkCache.updated(by: frame.clients, decode: decodeBase64)
        guard let client = selector.selection(in: frame, following: state.followedKey) else { return nil }
        state.followedKey = client.key
        return NowPlaying(
            title: client.title,
            artist: client.artist,
            artworkData: state.artworkCache.artwork(for: client.key),
            duration: client.duration,
            rawElapsed: client.elapsed,
            playbackRate: client.rate ?? 1.0,
            timestamp: client.timestamp.map { Date(timeIntervalSinceReferenceDate: $0) },
            pid: client.pid
        )
    }
}

private final class StreamStateBox: @unchecked Sendable {
    let lock = NSLock()
    var iterator: AsyncStream<String>.AsyncIterator?
    var isPolling = false
    var artworkCache = ArtworkCache()
    /// `HelperClient.key` of the client the last frame selected.
    var followedKey: String?
}
