import Dependencies
import Domain
import Testing

@testable import ProcessExecutor

@Suite("ProcessExecutorImpl")
struct ProcessExecutorImplTests {
    // MARK: - Timeout (the #340 raison d'être)

    @Test("times out deterministically when the child never completes — no real waiting")
    func timesOutOnHungChild() async throws {
        let gateway = FakeProcessGateway(.hang)
        let executor = withDependencies {
            // ImmediateClock resolves the timeout sleep instantly, so the timeout
            // branch fires with zero wall-clock — the deterministic replacement for
            // the pre-#340 "run a real subprocess and measure elapsed" oracle.
            $0.continuousClock = ImmediateClock()
            $0.processGateway = gateway
        } operation: {
            ProcessExecutorImpl()
        }

        let result = try await executor.run(
            executable: "/bin/sh", arguments: ["-c", "sleep 10"], environment: [:], timeoutMs: 100)

        #expect(result.status == -1)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.contains("timed out"))
    }

    @Test("returns the child's result when it completes before the timeout elapses")
    func returnsResultWhenChildCompletes() async throws {
        let gateway = FakeProcessGateway(.returns((status: 0, stdout: "hello", stderr: "")))
        let executor = withDependencies {
            // TestClock is never advanced, so the timeout sleep stays pending forever —
            // the completed child always wins the race. Deterministic, zero wall-clock.
            $0.continuousClock = TestClock()
            $0.processGateway = gateway
        } operation: {
            ProcessExecutorImpl()
        }

        let result = try await executor.run(
            executable: "/bin/echo", arguments: ["hello"], environment: [:], timeoutMs: 5000)

        #expect(result.status == 0)
        #expect(result.stdout == "hello")
    }

    // MARK: - No timeout (long-lived tools)

    @Test("nil timeout runs the child to completion and passes arguments straight through")
    func nilTimeoutPassesThrough() async throws {
        let gateway = FakeProcessGateway(.returns((status: 0, stdout: "done", stderr: "")))
        let executor = withDependencies {
            $0.processGateway = gateway
        } operation: {
            ProcessExecutorImpl()
        }

        let result = try await executor.run(
            executable: "/usr/bin/yt-dlp", arguments: ["-o", "out.mp4"], environment: ["A": "b"],
            timeoutMs: nil)

        #expect(result.status == 0)
        #expect(result.stdout == "done")
        #expect(gateway.lastCall?.executable == "/usr/bin/yt-dlp")
        #expect(gateway.lastCall?.arguments == ["-o", "out.mp4"])
        #expect(gateway.lastCall?.environment == ["A": "b"])
    }

    @Test("a non-finite timeout is treated as no timeout — never traps on Int(Double)")
    func nonFiniteTimeoutDoesNotTrap() async throws {
        let gateway = FakeProcessGateway(.returns((status: 0, stdout: "ok", stderr: "")))
        let executor = withDependencies {
            $0.processGateway = gateway
        } operation: {
            ProcessExecutorImpl()
        }

        let result = try await executor.run(
            executable: "/bin/echo", arguments: [], environment: [:], timeoutMs: .nan)

        #expect(result.status == 0)
        #expect(result.stdout == "ok")
    }

    // MARK: - Launch failure

    @Test("propagates the gateway's launch error instead of swallowing it")
    func propagatesLaunchError() async {
        let gateway = FakeProcessGateway(.throwsLaunchError)
        let executor = withDependencies {
            $0.continuousClock = TestClock()
            $0.processGateway = gateway
        } operation: {
            ProcessExecutorImpl()
        }

        await #expect(throws: FakeLaunchError.self) {
            try await executor.run(
                executable: "/nope", arguments: [], environment: [:], timeoutMs: 5000)
        }
    }
}
