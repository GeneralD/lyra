import Darwin
import Foundation
import TestSupport
import Testing

@testable import DarwinGateway

/// Thin real-subprocess smokes for `runProcess` (#340). These carry **no timing
/// oracle** — the deterministic timeout logic lives in `ProcessExecutor` and is
/// tested there with a fake clock. Here we only assert the OS primitive's contract:
/// status, captured stdout/stderr, environment pass-through, launch failure, and
/// that repeated short-lived spawns don't hang (the #308 regression class).
/// `.serialized` because real processes are global OS state (cf. #315).
@Suite("DarwinGateway.runProcess", .serialized, .timeLimit(.minutes(1)))
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

        try #require(await pollUntil { FileManager.default.fileExists(atPath: pidFile) })

        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test("a call from an already-cancelled task throws immediately without spawning")
    func preCancelledCallThrowsWithoutSpawning() async {
        let marker = NSTemporaryDirectory() + "lyra-runproc-\(UUID().uuidString).marker"
        defer { try? FileManager.default.removeItem(atPath: marker) }

        let task = Task { [gateway] in
            // Hold until cancellation is definitely observed, so runProcess enters with the
            // flag already set and takes the register-guard bail-out — no child is spawned.
            // `Task.sleep` throws `CancellationError` the instant `cancel()` lands, so this
            // never waits the full 30s on the passing path; it is a bound, not a delay.
            _ = try? await Task.sleep(for: .seconds(30))
            return try await gateway.runProcess(
                executable: "/bin/sh", arguments: ["-c", "echo x > '\(marker)'"], environment: [:])
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: marker), "a pre-cancelled call must not spawn")
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

        try #require(await pollUntil { FileManager.default.fileExists(atPath: readyFile) })
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }

        let pidString =
            (try? String(contentsOfFile: pidFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let pid = Int32(pidString) ?? 0
        #expect(pid > 0, "the child should have recorded its pid before ignoring SIGTERM")

        // The reap is asynchronous — poll rather than sleep a fixed interval.
        let reaped = await pollUntil { kill(pid, 0) != 0 }
        #expect(reaped, "a SIGTERM-ignoring child must be SIGKILLed, not left running")
    }

    @Test("cancellation landing mid-spawn kills the child via the markLaunched race")
    func cancelDuringSpawnClosesLaunchRace() async throws {
        // The injected spawn parks the child unlaunched until task cancellation
        // has landed inside requestCancel — widening the nanosecond window
        // between `Process.run()` returning and `markLaunched` into a
        // deterministic hit, then launching for real so the kill path runs on a
        // live process.
        let spawnEntered = Collector<Void>()
        let releaseSpawn = DispatchSemaphore(value: 0)
        final class ProcessBox: @unchecked Sendable { var process: Process? }
        let spawned = ProcessBox()
        let gateway = DarwinGateway(spawnProcess: { process in
            // Written before spawnEntered is recorded, so the test's
            // waitForCount below establishes the read.
            spawned.process = process
            spawnEntered.append(())
            releaseSpawn.wait()
            try process.run()
        })

        let task = Task {
            try await gateway.runProcess(
                executable: "/bin/sleep", arguments: ["30"], environment: [:])
        }

        await spawnEntered.waitForCount(1)
        task.cancel()
        // The continuation's registration closure is still synchronously parked
        // inside spawnProcess — the cancel-side resume is only buffered until
        // that closure returns, so the spawn must be released BEFORE awaiting
        // the task's result (the reverse order deadlocks).
        releaseSpawn.signal()
        // markLaunched observes the already-recorded termination request and
        // kills the just-spawned child itself; the buffered CancellationError
        // then delivers.
        await #expect(throws: CancellationError.self) { try await task.value }
        let child = try #require(spawned.process)
        try #require(await pollUntil { !child.isRunning })
    }
}
