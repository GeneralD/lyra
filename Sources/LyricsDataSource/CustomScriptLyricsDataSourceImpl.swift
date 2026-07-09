import Dependencies
import Domain
import Foundation
import os

public struct CustomScriptLyricsDataSourceImpl: Sendable {
    private let fallbackCommand: [String]
    private let timeoutMs: Double
    private let configDir: String
    private let cacheDir: String
    let processRunner:
        @Sendable (String, [String], [String: String], Double) async throws -> (
            status: Int32, stdout: String, stderr: String
        )

    public init() {
        @Dependency(\.configDataSource) var configDataSource
        let lyrics = configDataSource.load()?.config.lyrics
        self.init(
            fallbackCommand: lyrics?.fallbackCommand ?? [],
            timeoutMs: lyrics?.timeoutMs.value ?? 5000,
            configDir: configDataSource.configDir,
            cacheDir: Self.resolvedCacheDir(),
            processRunner: { executable, arguments, environment, timeoutMs in
                try await Self.executeProcess(
                    executable: executable, arguments: arguments, environment: environment, timeoutMs: timeoutMs)
            }
        )
    }

    init(
        fallbackCommand: [String],
        timeoutMs: Double,
        configDir: String,
        cacheDir: String,
        processRunner:
            @escaping @Sendable (String, [String], [String: String], Double) async throws -> (
                status: Int32, stdout: String, stderr: String
            )
    ) {
        self.fallbackCommand = fallbackCommand
        self.timeoutMs = timeoutMs
        self.configDir = configDir
        self.cacheDir = cacheDir
        self.processRunner = processRunner
    }

    private static func resolvedCacheDir() -> String {
        let base =
            ProcessInfo.processInfo.environment["XDG_CACHE_HOME"]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? "\(NSHomeDirectory())/.cache"
        return "\(base)/lyra"
    }
}

extension CustomScriptLyricsDataSourceImpl: LyricsDataSource {
    public func get(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? {
        guard let executable = fallbackCommand.first else { return nil }
        let arguments = Array(fallbackCommand.dropFirst()) + [title, artist]
        let environment = ["LYRA_CONFIG_DIR": configDir, "LYRA_CACHE_DIR": cacheDir]

        guard let (status, stdout, _) = try? await processRunner(executable, arguments, environment, timeoutMs),
            status == 0,
            let data = stdout.data(using: .utf8),
            let output = try? JSONDecoder().decode(ScriptOutput.self, from: data),
            let plainLyrics = output.plainLyrics, !plainLyrics.isEmpty
        else { return nil }

        return LyricsResult(trackName: output.trackName, artistName: output.artistName, plainLyrics: plainLyrics)
    }

    public func search(query: String) async -> [LyricsResult]? { nil }
}

private struct ScriptOutput: Decodable {
    let trackName: String?
    let artistName: String?
    let plainLyrics: String?

    enum CodingKeys: String, CodingKey {
        case trackName = "track_name"
        case artistName = "artist_name"
        case plainLyrics = "plain_lyrics"
    }
}

// MARK: - Async Process

extension CustomScriptLyricsDataSourceImpl {
    static func executeProcess(
        executable: String, arguments: [String], environment: [String: String], timeoutMs: Double
    ) async throws -> (status: Int32, stdout: String, stderr: String) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.environment = environment
            process.standardInput = FileHandle.nullDevice
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let buffer = ScriptProcessBuffer()
            let group = DispatchGroup()
            let hasResumed = OSAllocatedUnfairLock(initialState: false)

            // Registered before `run()` so there is no race with an already-exited
            // process (Foundation only guarantees delivery when the handler is set
            // ahead of termination). Paired with `group.leave()` here rather than a
            // post-hoc `waitUntilExit()`, which has been empirically observed to hang
            // indefinitely after repeated short-lived invocations (#308 review).
            group.enter()
            process.terminationHandler = { _ in group.leave() }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            group.enter()
            DispatchQueue.global().async {
                buffer.stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
            group.enter()
            DispatchQueue.global().async {
                buffer.stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }

            let timeoutWorkItem = DispatchWorkItem {
                let shouldResume = hasResumed.withLock { done -> Bool in
                    guard !done else { return false }
                    done = true
                    return true
                }
                guard shouldResume else { return }
                process.terminate()
                continuation.resume(returning: (-1, "", "timed out after \(Int(timeoutMs))ms"))
            }
            DispatchQueue.global().asyncAfter(
                deadline: .now() + .milliseconds(Int(timeoutMs)), execute: timeoutWorkItem)

            group.notify(queue: .global()) {
                let shouldResume = hasResumed.withLock { done -> Bool in
                    guard !done else { return false }
                    done = true
                    return true
                }
                guard shouldResume else { return }
                timeoutWorkItem.cancel()
                // All three members (stdout drain, stderr drain, terminationHandler)
                // have completed, so terminationStatus is already valid to read —
                // no blocking waitUntilExit() call needed on the success path.
                continuation.resume(
                    returning: (process.terminationStatus, buffer.stdoutTrimmed, buffer.stderrTrimmed))
            }
        }
    }
}

/// Accumulates stdout/stderr from concurrent pipe-drain tasks. `@unchecked Sendable`
/// because each property is written by exactly one DispatchQueue task and read only
/// after the DispatchGroup barrier — no lock needed (mirrors YouTubeWallpaperDataSourceImpl's PipeBuffer).
private final class ScriptProcessBuffer: @unchecked Sendable {
    var stdout = Data()
    var stderr = Data()

    var stdoutTrimmed: String { trimmed(stdout) }
    var stderrTrimmed: String { trimmed(stderr) }

    private func trimmed(_ data: Data) -> String {
        String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
