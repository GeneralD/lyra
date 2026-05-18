import CryptoKit
import Dependencies
import Domain
import Files
import Foundation

public final class MediaRemoteDataSourceImpl: @unchecked Sendable {
    @Dependency(\.processGateway) private var gateway

    private let state = StreamStateBox()
    private let cacheHomeOverride: String?
    private let executableBox = ExecutablePathBox()

    public init(cacheHome: String? = nil) {
        cacheHomeOverride = cacheHome?.trimmingCharacters(in: .whitespacesAndNewlines)
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
    private func ensureExecutable() -> String? {
        executableBox.resolve(build: buildExecutable)
    }

    private func buildExecutable() -> String? {
        let sourceName = "media-remote-helper"
        let arch = currentArchitecture
        let binaryName = "\(sourceName)-\(arch)"
        let shaFileName = "\(binaryName).swift.sha"
        let cacheDir = lyraCacheDirectory()
        let binaryPath = "\(cacheDir)/\(binaryName)"
        let shaPath = "\(cacheDir)/\(shaFileName)"

        guard
            let sourceURL = Bundle.module.url(forResource: sourceName, withExtension: "swift"),
            let sourceData = try? Data(contentsOf: sourceURL)
        else { return nil }

        let currentSHA = SHA256.hash(data: sourceData).map { String(format: "%02x", $0) }.joined()
        let cachedSHA =
            (try? String(contentsOfFile: shaPath, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let binaryExists = FileManager.default.isExecutableFile(atPath: binaryPath)

        if binaryExists, cachedSHA == currentSHA {
            return binaryPath
        }

        try? FileManager.default.createDirectory(
            atPath: cacheDir, withIntermediateDirectories: true)

        let exitCode = gateway.run(
            executable: "/usr/bin/env",
            arguments: ["swiftc", "-O", sourceURL.path, "-o", binaryPath]
        )
        guard exitCode == 0 else {
            FileHandle.standardError.write(
                Data(
                    "lyra: failed to compile media-remote-helper (swiftc exit \(exitCode))\n".utf8))
            return nil
        }

        try? currentSHA.write(toFile: shaPath, atomically: true, encoding: .utf8)
        return binaryPath
    }

    private func lyraCacheDirectory() -> String {
        let resolved = resolvedCacheRoot()
        return "\(resolved)/lyra"
    }

    private func resolvedCacheRoot() -> String {
        if let override = cacheHomeOverride, !override.isEmpty { return override }
        let env = ProcessInfo.processInfo.environment["XDG_CACHE_HOME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let env, !env.isEmpty { return env }
        return URL(fileURLWithPath: Folder.home.path)
            .appendingPathComponent(".cache", isDirectory: true)
            .path
    }

    private var currentArchitecture: String {
        #if arch(arm64)
            return "arm64"
        #elseif arch(x86_64)
            return "x86_64"
        #else
            return "unknown"
        #endif
    }
}

extension MediaRemoteDataSourceImpl {
    private func takeIterator() -> AsyncStream<String>.AsyncIterator? {
        let executablePath = ensureExecutable()

        state.lock.lock()
        defer { state.lock.unlock() }

        guard !state.isPolling else { return nil }
        if state.iterator == nil {
            guard let executablePath else {
                state.isPolling = true
                return AsyncStream<String> { $0.finish() }.makeAsyncIterator()
            }
            let stream = gateway.runStreaming(executable: executablePath, arguments: [])
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

private final class ExecutablePathBox: @unchecked Sendable {
    private let lock = NSLock()
    private var resolvedPath: String?

    func resolve(build: () -> String?) -> String? {
        lock.lock()
        defer { lock.unlock() }
        if let resolvedPath { return resolvedPath }
        resolvedPath = build()
        return resolvedPath
    }
}
