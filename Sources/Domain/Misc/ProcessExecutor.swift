import Dependencies

/// Runs a subprocess with an optional timeout, capturing stdout/stderr.
///
/// This is the DataSource-tier collaborator that both `CustomScriptLyricsDataSourceImpl`
/// and `YouTubeWallpaperDataSourceImpl` share instead of each carrying its own
/// `executeProcess` static (#340). It sits directly above `ProcessGateway`:
///
/// - the **executor** owns the clock-driven timeout race (`@Dependency(\.continuousClock)`),
///   so a hung child is detected deterministically in tests — no real waiting;
/// - the **gateway** (`runProcess`) owns spawning + non-blocking drain + cancellation.
///
/// Separating the two is what makes the timeout logic testable: the flaky
/// pre-#340 tests could only assert timeout by running a real subprocess and
/// measuring wall-clock, whose oracle was hostage to CI scheduling.
public protocol ProcessExecutor: Sendable {
    /// - Parameters:
    ///   - timeoutMs: milliseconds before the child is killed and a
    ///     `(-1, "", "timed out after …ms")` result returned. Only `nil` disables
    ///     the timeout — used for long-lived, low-frequency tools like yt-dlp /
    ///     ffmpeg, which must run to completion. Non-nil values are normalized:
    ///     finite ones clamp to 1 ms … 1 h, non-finite ones fall back to a 5 s
    ///     default — a configured timeout can never disable itself by accident.
    /// - Returns: the child's exit status plus trimmed stdout/stderr.
    func run(
        executable: String, arguments: [String], environment: [String: String], timeoutMs: Double?
    ) async throws -> (status: Int32, stdout: String, stderr: String)
}

public enum ProcessExecutorKey: TestDependencyKey {
    public static let testValue: any ProcessExecutor = UnimplementedProcessExecutor()
}

extension DependencyValues {
    public var processExecutor: any ProcessExecutor {
        get { self[ProcessExecutorKey.self] }
        set { self[ProcessExecutorKey.self] = newValue }
    }
}

private struct UnimplementedProcessExecutor: ProcessExecutor {
    func run(
        executable: String, arguments: [String], environment: [String: String], timeoutMs: Double?
    ) async throws -> (status: Int32, stdout: String, stderr: String) {
        fatalError("ProcessExecutor.run not implemented")
    }
}
