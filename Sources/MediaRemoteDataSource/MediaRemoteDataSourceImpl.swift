import Dependencies
import Domain
import Foundation

public final class MediaRemoteDataSourceImpl: @unchecked Sendable {
    @Dependency(\.processGateway) private var gateway

    private let state = StreamStateBox()

    public init() {}
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

        guard let data = line.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            json["has_info"] as? Bool == true
        else {
            return .noInfo
        }

        return .info(
            NowPlaying(
                title: json["title"] as? String,
                artist: json["artist"] as? String,
                artworkData: (json["artwork_base64"] as? String).flatMap { Data(base64Encoded: $0) },
                duration: json["duration"] as? Double,
                rawElapsed: json["elapsed"] as? Double,
                playbackRate: json["rate"] as? Double ?? 1.0,
                timestamp: (json["timestamp"] as? Double).map {
                    Date(timeIntervalSinceReferenceDate: $0)
                }
            ))
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
}

private final class StreamStateBox: @unchecked Sendable {
    let lock = NSLock()
    var iterator: AsyncStream<String>.AsyncIterator?
    var isPolling = false
}
