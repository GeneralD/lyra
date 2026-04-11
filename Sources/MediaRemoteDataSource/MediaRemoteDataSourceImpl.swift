import Dependencies
import Domain
import Files
import Foundation
import os

public final class MediaRemoteDataSourceImpl: @unchecked Sendable {
    @Dependency(\.processGateway) private var gateway

    private let lock = OSAllocatedUnfairLock(initialState: false)
    private var iterator: AsyncStream<String>.AsyncIterator?
    private static let scriptPath: String = ensureScript()

    public init() {}
}

extension MediaRemoteDataSourceImpl: MediaRemoteDataSource {
    public func poll() async -> MediaRemotePollResult {
        let needsInit = lock.withLock { state in
            guard !state else { return false }
            state = true
            return true
        }
        if needsInit {
            let stream = gateway.runStreaming(
                executable: "/usr/bin/env", arguments: ["swift", Self.scriptPath])
            iterator = stream.makeAsyncIterator()
        }

        guard let line = await iterator?.next() else {
            lock.withLock { $0 = false }
            iterator = nil
            return .eof
        }

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
        try? FileManager.default.removeItem(atPath: destPath)
        try? FileManager.default.copyItem(atPath: source.path, toPath: destPath)
        return destPath
    }
}
