import Darwin
import Domain
import Foundation
import os

// Async subprocess primitive for `ProcessExecutor` (#340). Split from DarwinGateway.swift
// to keep that file focused and under the line budget; the conformance is completed here.
extension DarwinGateway {
    public func runProcess(
        executable: String, arguments: [String], environment: [String: String]
    ) async throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let state = RunProcessState()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<(status: Int32, stdout: String, stderr: String), Error>) in
                // If cancellation already fired, bail before spawning anything.
                guard state.register(continuation) else {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                let group = DispatchGroup()

                // Registered before run() so an already-exited process still delivers its
                // termination (Foundation only guarantees delivery when set ahead of exit) —
                // paired with group.leave() instead of a post-hoc waitUntilExit(), which was
                // observed to hang after repeated short-lived invocations (#308).
                group.enter()
                process.terminationHandler = { _ in group.leave() }

                // Non-blocking drain: readabilityHandler fires on a dispatch source as bytes
                // arrive, so no thread-pool thread is parked on readDataToEndOfFile for the
                // child's whole lifetime — that parking was the #340 pool-exhaustion cause.
                group.enter()
                drainPipe(stdoutPipe.fileHandleForReading, into: { state.appendStdout($0) }, onEOF: { group.leave() })
                group.enter()
                drainPipe(stderrPipe.fileHandleForReading, into: { state.appendStderr($0) }, onEOF: { group.leave() })

                do {
                    try process.run()
                } catch {
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    process.terminationHandler = nil
                    state.resume(with: .failure(error))
                    return
                }

                // Close the launch/cancel race: if cancellation requested termination before
                // the child existed, kill it now that it is running.
                if let killTarget = state.markLaunched(process) {
                    terminateProcess(killTarget)
                }

                group.notify(queue: .global()) {
                    state.resume(
                        with: .success((process.terminationStatus, state.stdoutTrimmed, state.stderrTrimmed)))
                }
            }
        } onCancel: {
            // Resume the continuation with CancellationError *immediately* — do NOT wait for
            // the pipes to drain. A SIGTERM-ignoring script's orphaned grandchild can hold
            // the pipe open long past the kill, and the executor's timeout must return
            // promptly regardless (#340). The child is signalled here; the leaked drain
            // finishes and is ignored (resume-once) whenever the grandchild finally exits.
            let (killTarget, continuation) = state.requestCancel()
            if let killTarget { terminateProcess(killTarget) }
            continuation?.resume(throwing: CancellationError())
        }
    }
}

/// Installs a non-blocking readabilityHandler that accumulates bytes and signals EOF
/// (an empty read) exactly once, detaching itself.
private func drainPipe(
    _ handle: FileHandle, into append: @escaping @Sendable (Data) -> Void, onEOF: @escaping @Sendable () -> Void
) {
    handle.readabilityHandler = { handle in
        let data = handle.availableData
        guard !data.isEmpty else {
            handle.readabilityHandler = nil
            onEOF()
            return
        }
        append(data)
    }
}

/// SIGTERM, then SIGKILL after a short grace if the child ignores the polite signal —
/// so a script trapping SIGTERM cannot outlive the executor's timeout. Both signals are
/// gated on this `Process` instance's own `isRunning` rather than `kill(pid, 0)`: while
/// it is true the child is unreaped and the pid is still ours, so a pid recycled to an
/// unrelated process after a prompt exit can never be targeted. The captured instance
/// also keeps Foundation's reaping alive through the grace window. Targets the specific
/// pid (never the process group) so lyra itself is never at risk; a shell script's own
/// grandchildren are outside this guarantee.
private func terminateProcess(_ process: Process) {
    guard process.isRunning else { return }
    kill(process.processIdentifier, SIGTERM)
    DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(500)) {
        guard process.isRunning else { return }
        kill(process.processIdentifier, SIGKILL)
    }
}

/// Coordinates the checked continuation, byte accumulation, and the launch/cancel races
/// for a single `runProcess` call. `@unchecked Sendable`: every field is touched only
/// inside `lock`.
private final class RunProcessState: @unchecked Sendable {
    typealias Continuation = CheckedContinuation<(status: Int32, stdout: String, stderr: String), Error>

    private let lock = OSAllocatedUnfairLock()
    private var continuation: Continuation?
    private var resumed = false
    private var terminateRequested = false
    private var launched: Process?
    private var stdout = Data()
    private var stderr = Data()

    /// Registers the continuation. Returns `false` if cancellation already fired (the
    /// caller must resume-throw itself), `true` to proceed with spawning.
    func register(_ newContinuation: Continuation) -> Bool {
        lock.withLock {
            continuation = newContinuation
            return !terminateRequested
        }
    }

    func appendStdout(_ data: Data) { lock.withLock { stdout.append(data) } }
    func appendStderr(_ data: Data) { lock.withLock { stderr.append(data) } }
    var stdoutTrimmed: String { lock.withLock { Self.trimmed(stdout) } }
    var stderrTrimmed: String { lock.withLock { Self.trimmed(stderr) } }

    /// Marks the child launched, recording the `Process` instance (not just its pid, so
    /// a later kill can verify identity via `isRunning`). Returns it iff a termination
    /// was already requested (cancel raced ahead of the launch) so the caller kills now.
    func markLaunched(_ newProcess: Process) -> Process? {
        lock.withLock {
            launched = newProcess
            return terminateRequested ? newProcess : nil
        }
    }

    /// Handles cancellation atomically: records the request, and returns the `Process`
    /// to kill (if the child is already launched) plus the continuation to resume-throw
    /// (if it is set and not yet resumed). The caller performs both outside the lock.
    func requestCancel() -> (killTarget: Process?, continuation: Continuation?) {
        lock.withLock {
            terminateRequested = true
            let killTarget = launched
            guard !resumed else { return (killTarget, nil) }
            resumed = true
            defer { continuation = nil }
            return (killTarget, continuation)
        }
    }

    /// Resumes the continuation exactly once for normal completion / launch failure; the
    /// losing side of a completion-vs-cancel race is ignored.
    func resume(with result: Result<(status: Int32, stdout: String, stderr: String), Error>) {
        let pending = lock.withLock { () -> Continuation? in
            guard !resumed else { return nil }
            resumed = true
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(with: result)
    }

    private static func trimmed(_ data: Data) -> String {
        String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
