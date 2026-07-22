import Darwin
import Foundation
import Testing

@testable import DarwinGateway

/// Thin real-subprocess smokes for `runProcess` (#340). These carry **no timing
/// oracle** — the deterministic timeout logic lives in `ProcessExecutor` and is
/// tested there with a fake clock. Here we only assert the OS primitive's contract:
/// status, captured stdout/stderr, environment pass-through, launch failure, and
/// that repeated short-lived spawns don't hang (the #308 regression class).
/// `.serialized` because real processes are global OS state (cf. #315).
@Suite("DarwinGateway.runProcess", .serialized)
struct DarwinGatewayRunProcessTests {
    private let gateway = DarwinGateway()

    @Test("captures stdout and a zero status from a successful command")
    func capturesStdout() async throws {
        let result = try await gateway.runProcess(
            executable: "/bin/echo", arguments: ["hi there"], environment: [:])
        #expect(result.status == 0)
        #expect(result.stdout == "hi there")
    }

    @Test("captures stderr and a non-zero status")
    func capturesStderrAndExitCode() async throws {
        let result = try await gateway.runProcess(
            executable: "/bin/sh", arguments: ["-c", "echo oops 1>&2; exit 3"], environment: [:])
        #expect(result.status == 3)
        #expect(result.stderr.contains("oops"))
    }

    @Test("passes the environment through to the child")
    func passesEnvironment() async throws {
        let result = try await gateway.runProcess(
            executable: "/bin/sh", arguments: ["-c", "printf %s \"$FOO\""], environment: ["FOO": "bar"])
        #expect(result.status == 0)
        #expect(result.stdout == "bar")
    }

    @Test("throws when the executable cannot be launched")
    func throwsOnLaunchFailure() async {
        await #expect(throws: (any Error).self) {
            try await gateway.runProcess(
                executable: "/nonexistent/definitely-not-real-xyz", arguments: [], environment: [:])
        }
    }

    @Test("repeated short-lived spawns complete without hanging (#308 regression guard)")
    func repeatedSpawnsDoNotHang() async throws {
        for i in 0..<50 {
            let result = try await gateway.runProcess(
                executable: "/bin/echo", arguments: ["n-\(i)"], environment: [:])
            #expect(result.status == 0)
            #expect(result.stdout == "n-\(i)")
        }
    }

    @Test("cancelling the task terminates the child and throws instead of waiting it out")
    func cancellationTerminatesChild() async throws {
        let pidFile = NSTemporaryDirectory() + "lyra-runproc-\(UUID().uuidString).pid"
        defer { try? FileManager.default.removeItem(atPath: pidFile) }

        let task = Task {
            try await gateway.runProcess(
                executable: "/bin/sh",
                arguments: ["-c", "echo $$ > '\(pidFile)'; sleep 5"],
                environment: [:])
        }

        let deadline = ContinuousClock.now + .seconds(1)
        while !FileManager.default.fileExists(atPath: pidFile), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test("cancellation SIGKILLs a child that ignores SIGTERM")
    func cancellationForceKillsStubbornChild() async throws {
        let pidFile = NSTemporaryDirectory() + "lyra-runproc-\(UUID().uuidString).pid"
        let readyFile = NSTemporaryDirectory() + "lyra-runproc-\(UUID().uuidString).ready"
        defer {
            try? FileManager.default.removeItem(atPath: pidFile)
            try? FileManager.default.removeItem(atPath: readyFile)
        }

        // The child records its own pid, traps (ignores) SIGTERM, then signals readiness.
        let task = Task {
            try await gateway.runProcess(
                executable: "/bin/sh",
                arguments: ["-c", "echo $$ > '\(pidFile)'; trap '' TERM; echo ready > '\(readyFile)'; sleep 3"],
                environment: [:])
        }

        let deadline = ContinuousClock.now + .seconds(1)
        while !FileManager.default.fileExists(atPath: readyFile), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }

        let pidString =
            (try? String(contentsOfFile: pidFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let pid = Int32(pidString) ?? 0
        #expect(pid > 0, "the child should have recorded its pid before ignoring SIGTERM")

        // The reap is asynchronous — poll rather than sleep a fixed interval.
        let deadline = ContinuousClock.now + .seconds(3)
        while kill(pid, 0) == 0, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(kill(pid, 0) != 0, "a SIGTERM-ignoring child must be SIGKILLed, not left running")
    }
}
