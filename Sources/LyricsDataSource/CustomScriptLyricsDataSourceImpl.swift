import Dependencies
import Domain
import Foundation
import os

public struct CustomScriptLyricsDataSourceImpl: Sendable {
    // Config values (fallback_command, timeout_ms, configDir) are deliberately NOT
    // captured here at init — `configDataSource` is read fresh inside `get()` on every
    // call, mirroring LLMMetadataDataSourceImpl, so an edited [lyrics] section takes
    // effect on the daemon's very next lookup without a restart (#41).
    @Dependency(\.configDataSource) private var configDataSource
    let processRunner:
        @Sendable (String, [String], [String: String], Double) async throws -> (
            status: Int32, stdout: String, stderr: String
        )

    public init() {
        self.init(processRunner: { executable, arguments, environment, timeoutMs in
            try await Self.executeProcess(
                executable: executable, arguments: arguments, environment: environment, timeoutMs: timeoutMs)
        })
    }

    // Test seam: inject a processRunner spy/stub. Config values are supplied via
    // `@Dependency(\.configDataSource)` — tests override it with `withDependencies`.
    init(
        processRunner:
            @escaping @Sendable (String, [String], [String: String], Double) async throws -> (
                status: Int32, stdout: String, stderr: String
            )
    ) {
        self.processRunner = processRunner
    }

    static func resolvedCacheDir() -> String {
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
        // Read config fresh on every call (never captured at init) so an edited
        // fallback_command/timeout_ms takes effect on the daemon's next lookup (#41).
        let lyrics = configDataSource.load()?.config.lyrics
        let fallbackCommand = lyrics?.fallbackCommand ?? []
        let timeoutMs = lyrics?.timeoutMs.value ?? 5000
        let configDir = configDataSource.configDir
        let cacheDir = Self.resolvedCacheDir()

        // Placeholders expand BEFORE the absolute-path guard so a config can lead with
        // "$LYRA_CONFIG_DIR/..." and still satisfy the absolute-executable contract.
        let command = fallbackCommand.map { Self.expandedPlaceholders($0, configDir: configDir, cacheDir: cacheDir) }
        // The executable must be an absolute path — a launchd-run daemon has a minimal
        // PATH, so relative paths (resolved against the daemon's CWD) would behave
        // unpredictably and diverge from the documented contract. Reject them up front.
        guard let executable = command.first, executable.hasPrefix("/") else { return nil }
        let arguments = Array(command.dropFirst()) + [title, artist]
        // Merge onto the parent environment rather than replacing it — Process.environment
        // REPLACES the child's entire environment when set, and the user's custom script
        // still needs PATH/HOME/LANG/etc. to run like a normal subprocess (#308 review).
        let environment = ProcessInfo.processInfo.environment.merging(
            ["LYRA_CONFIG_DIR": configDir, "LYRA_CACHE_DIR": cacheDir]
        ) { _, new in new }

        // Require a non-empty track_name: LyricsMatchValidator skips the title-similarity
        // check when the result title is nil/empty, so a script that emits only
        // plain_lyrics (or a generic response) would otherwise slip past validation and
        // reintroduce the unvalidated-cache path Tier C exists to prevent.
        guard let (status, stdout, _) = try? await processRunner(executable, arguments, environment, timeoutMs),
            status == 0,
            let data = stdout.data(using: .utf8),
            let output = try? JSONDecoder().decode(ScriptOutput.self, from: data),
            let trackName = output.trackName, !trackName.isEmpty,
            let plainLyrics = output.plainLyrics, !plainLyrics.isEmpty
        else { return nil }

        return LyricsResult(trackName: trackName, artistName: output.artistName, plainLyrics: plainLyrics)
    }

    public func search(query: String) async -> [LyricsResult]? { nil }

    /// Expands `$LYRA_CONFIG_DIR` / `$LYRA_CACHE_DIR` (and their `${…}` forms) in a
    /// fallback_command element, so configs can locate scripts relative to lyra's own
    /// directories instead of hardcoding machine-specific absolute paths.
    private static func expandedPlaceholders(_ element: String, configDir: String, cacheDir: String) -> String {
        [
            ("${LYRA_CONFIG_DIR}", configDir), ("$LYRA_CONFIG_DIR", configDir),
            ("${LYRA_CACHE_DIR}", cacheDir), ("$LYRA_CACHE_DIR", cacheDir),
        ].reduce(element) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }
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
        // timeout_ms comes straight from user config: clamp to a finite sane window
        // (1 ms … 1 h) before Int conversion — Int(Double) traps on NaN/±inf/
        // out-of-range, which would let a pathological config value crash the daemon.
        let timeoutMs = timeoutMs.isFinite ? min(max(timeoutMs, 1), 3_600_000) : 5000
        return try await withCheckedThrowingContinuation { continuation in
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
                // SIGTERM first, then escalate to SIGKILL on the direct child pid if it
                // ignores the polite signal — otherwise a custom script that traps SIGTERM
                // keeps running after lyra has moved on, defeating the configured timeout.
                // Target the specific pid (never the process group) so lyra itself is never
                // at risk; a shell script's own grandchildren are outside this guarantee.
                process.terminate()
                let pid = process.processIdentifier
                DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(500)) {
                    if process.isRunning { kill(pid, SIGKILL) }
                }
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
