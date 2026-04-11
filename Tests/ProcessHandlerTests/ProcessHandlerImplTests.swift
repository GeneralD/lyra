import Dependencies
import Domain
import Testing

@testable import ProcessHandler

@Suite("ProcessHandlerImpl")
struct ProcessHandlerImplTests {
    // MARK: - start

    @Suite("start")
    struct Start {
        @Test("returns alreadyRunning when lock is held")
        func lockedReturnsAlreadyRunning() {
            withDependencies {
                $0.processGateway = StubProcessGateway(locked: true)
            } operation: {
                let result = ProcessHandlerImpl().start()
                guard case .failure(.alreadyRunning) = result else {
                    Issue.record("Expected .alreadyRunning")
                    return
                }
            }
        }

        @Test("returns alreadyRunning when overlay PIDs exist")
        func pidsReturnsAlreadyRunning() {
            withDependencies {
                $0.processGateway = StubProcessGateway(pids: [12345])
            } operation: {
                let result = ProcessHandlerImpl().start()
                guard case .failure(.alreadyRunning) = result else {
                    Issue.record("Expected .alreadyRunning")
                    return
                }
            }
        }

        @Test("returns spawnFailed when gateway fails to spawn")
        func spawnFailed() {
            withDependencies {
                $0.processGateway = StubProcessGateway(spawnResult: nil)
            } operation: {
                let result = ProcessHandlerImpl().start()
                guard case .failure(.spawnFailed) = result else {
                    Issue.record("Expected .spawnFailed, got \(result)")
                    return
                }
            }
        }

        @Test("returns daemonExitedImmediately when spawned daemon dies before health check")
        func daemonExitedImmediately() {
            withDependencies {
                $0.processGateway = StubProcessGateway(spawnResult: 42)
            } operation: {
                let result = ProcessHandlerImpl().start()
                guard case .failure(.daemonExitedImmediately) = result else {
                    Issue.record("Expected .daemonExitedImmediately, got \(result)")
                    return
                }
            }
        }

        @Test("returns started with PID on success")
        func success() {
            withDependencies {
                $0.processGateway = StubProcessGateway(spawnResult: 42, runningPIDs: [42])
            } operation: {
                let result = ProcessHandlerImpl().start()
                guard case .success(.started(let pid)) = result else {
                    Issue.record("Expected .started, got \(result)")
                    return
                }
                #expect(pid == 42)
            }
        }
    }

    // MARK: - stop

    @Suite("stop")
    struct Stop {
        @Test("returns notRunning when no PIDs and lock is free")
        func noPidsNoLock() {
            withDependencies {
                $0.processGateway = StubProcessGateway()
            } operation: {
                let result = ProcessHandlerImpl().stop()
                guard case .success(.notRunning) = result else {
                    Issue.record("Expected .notRunning")
                    return
                }
            }
        }

        @Test("cleans up stale lock when no PIDs but lock is held")
        func staleLock() {
            let spy = SpyProcessGateway(locked: true)
            withDependencies {
                $0.processGateway = spy
            } operation: {
                let result = ProcessHandlerImpl().stop()
                guard case .success(.notRunning) = result else {
                    Issue.record("Expected .notRunning")
                    return
                }
            }
            #expect(spy.releaseLockCalled)
        }
    }

    // MARK: - restart

    @Suite("restart")
    struct Restart {
        @Test("returns stopFailed when stop fails")
        func stopFails() {
            // PIDs exist but isRunning always true → stop can't kill → lockReleaseTimedOut → restart fails
            withDependencies {
                $0.processGateway = StubProcessGateway(pids: [99], locked: true, runningPIDs: [99])
            } operation: {
                let result = ProcessHandlerImpl().restart()
                guard case .failure(.stopFailed) = result else {
                    Issue.record("Expected .stopFailed, got \(result)")
                    return
                }
            }
        }
    }

    // MARK: - acquireDaemonLock

    @Suite("acquireDaemonLock")
    struct AcquireDaemonLock {
        @Test("delegates to gateway.acquireLock")
        func delegates() {
            withDependencies {
                $0.processGateway = StubProcessGateway(acquireResult: true)
            } operation: {
                #expect(ProcessHandlerImpl().acquireDaemonLock())
            }
        }

        @Test("returns false when lock fails")
        func fails() {
            withDependencies {
                $0.processGateway = StubProcessGateway(acquireResult: false)
            } operation: {
                #expect(!ProcessHandlerImpl().acquireDaemonLock())
            }
        }
    }
}

// MARK: - Stubs

private struct StubProcessGateway: ProcessGateway {
    var pids: [Int32] = []
    var locked: Bool = false
    var spawnResult: Int32? = 42
    var acquireResult: Bool = false
    var runningPIDs: Set<Int32> = []

    var resourceSnapshot: ResourceSnapshot { .init(cpuUser: 0, cpuSystem: 0, peakRSS: 0, currentRSS: 0) }
    var overlayPIDs: [Int32] { pids }
    func spawnDaemon(executablePath: String) -> Int32? { spawnResult }
    func sendSignal(_ pid: Int32, signal: Int32) -> Bool { true }
    func isRunning(_ pid: Int32) -> Bool { runningPIDs.contains(pid) }
    func acquireLock() -> Bool { acquireResult }
    var isLocked: Bool { locked }
    func releaseLock() {}
    func runLaunchctl(_ arguments: [String]) -> Int32 { 0 }
    func findExecutable(_ name: String) -> String? { nil }
    func run(executable: String, arguments: [String]) -> Int32 { 0 }
    func runCapturingOutput(executable: String, arguments: [String]) -> String? { nil }
    func runStreaming(executable: String, arguments: [String]) -> AsyncStream<String> {
        AsyncStream { $0.finish() }
    }
}

private final class SpyProcessGateway: ProcessGateway, @unchecked Sendable {
    var locked: Bool
    private(set) var releaseLockCalled = false

    init(locked: Bool = false) { self.locked = locked }

    var resourceSnapshot: ResourceSnapshot { .init(cpuUser: 0, cpuSystem: 0, peakRSS: 0, currentRSS: 0) }
    var overlayPIDs: [Int32] { [] }
    func spawnDaemon(executablePath: String) -> Int32? { nil }
    func sendSignal(_ pid: Int32, signal: Int32) -> Bool { true }
    func isRunning(_ pid: Int32) -> Bool { false }
    func acquireLock() -> Bool { false }
    var isLocked: Bool { locked }
    func releaseLock() {
        releaseLockCalled = true
        locked = false
    }
    func runLaunchctl(_ arguments: [String]) -> Int32 { 0 }
    func findExecutable(_ name: String) -> String? { nil }
    func run(executable: String, arguments: [String]) -> Int32 { 0 }
    func runCapturingOutput(executable: String, arguments: [String]) -> String? { nil }
    func runStreaming(executable: String, arguments: [String]) -> AsyncStream<String> {
        AsyncStream { $0.finish() }
    }
}
