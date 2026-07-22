import Dependencies
import Domain

public struct ProcessExecutorImpl: Sendable {
    @Dependency(\.continuousClock) private var clock
    @Dependency(\.processGateway) private var gateway

    public init() {}
}

extension ProcessExecutorImpl: ProcessExecutor {
    public func run(
        executable: String, arguments: [String], environment: [String: String], timeoutMs: Double?
    ) async throws -> (status: Int32, stdout: String, stderr: String) {
        let gateway = self.gateway

        // No timeout: run to completion. Only `nil` means "don't race a timer" — used
        // for long-lived tools (yt-dlp/ffmpeg) that must finish.
        guard let timeoutMs else {
            return try await gateway.runProcess(
                executable: executable, arguments: arguments, environment: environment)
        }

        // A non-nil but invalid value clamps instead of disabling: a config typo like
        // `timeout_ms = 0` (or NaN/±inf) must still bound the child — the pre-#340
        // contract. Finite values clamp to a sane window (1 ms … 1 h), non-finite ones
        // fall back to the 5 s default; both keep `Int(Double)` from trapping.
        let clampedMs = timeoutMs.isFinite ? Int(min(max(timeoutMs, 1), 3_600_000)) : 5000
        let clock = self.clock

        return try await withThrowingTaskGroup(of: Outcome.self) { group in
            group.addTask {
                .completed(
                    try await gateway.runProcess(
                        executable: executable, arguments: arguments, environment: environment))
            }
            group.addTask {
                try await clock.sleep(for: .milliseconds(clampedMs))
                return .timedOut
            }
            // The first child to finish (or throw) decides the outcome. A launch error
            // surfaces from the gateway task here and propagates. When the timeout wins,
            // `cancelAll()` cancels the still-running gateway task — `runProcess` then
            // terminates the child and throws `CancellationError`, discarded on scope exit.
            defer { group.cancelAll() }
            switch try await group.next()! {
            case .completed(let result):
                return result
            case .timedOut:
                return (status: -1, stdout: "", stderr: "timed out after \(clampedMs)ms")
            }
        }
    }
}

private enum Outcome: Sendable {
    case completed((status: Int32, stdout: String, stderr: String))
    case timedOut
}
