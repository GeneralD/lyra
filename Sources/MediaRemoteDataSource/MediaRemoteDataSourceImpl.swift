import Dependencies
import Domain
import Files
import Foundation

public final class MediaRemoteDataSourceImpl: @unchecked Sendable {
    @Dependency(\.processGateway) private var gateway

    private let state = StreamStateBox()
    private static let scriptPath: String = ensureScript()

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
    private static func ensureScript() -> String {
        let scriptName = "media-remote-helper.swift"
        let envCache = ProcessInfo.processInfo.environment["XDG_CACHE_HOME"]?.trimmingCharacters(
            in: .whitespacesAndNewlines)
        let cachePath =
            (envCache?.isEmpty == false) ? envCache! : "\(Folder.home.path).cache"
        let lyraCachePath = "\(cachePath)/lyra"
        try? FileManager.default.createDirectory(atPath: lyraCachePath, withIntermediateDirectories: true)
        guard let lyraFolder = try? Folder(path: lyraCachePath) else {
            return "\(lyraCachePath)/\(scriptName)"
        }

        let destFile = try? lyraFolder.createFileIfNeeded(withName: scriptName)
        let destPath = destFile?.path ?? "\(lyraCachePath)/\(scriptName)"
        guard let source = Bundle.module.url(forResource: "media-remote-helper", withExtension: "swift")
        else {
            return destPath
        }

        let fileManager = FileManager.default
        let needsCopy: Bool
        if fileManager.fileExists(atPath: destPath),
            let sourceData = try? Data(contentsOf: source),
            let destData = try? Data(contentsOf: URL(fileURLWithPath: destPath))
        {
            needsCopy = sourceData != destData
        } else {
            needsCopy = true
        }

        if needsCopy {
            try? fileManager.removeItem(atPath: destPath)
            try? fileManager.copyItem(atPath: source.path, toPath: destPath)
        }
        return destPath
    }
}

extension MediaRemoteDataSourceImpl {
    private func takeIterator() -> AsyncStream<String>.AsyncIterator? {
        state.lock.lock()
        defer { state.lock.unlock() }

        guard !state.isPolling else { return nil }
        if state.iterator == nil {
            let stream = gateway.runStreaming(
                executable: "/usr/bin/env", arguments: ["swift", Self.scriptPath])
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
