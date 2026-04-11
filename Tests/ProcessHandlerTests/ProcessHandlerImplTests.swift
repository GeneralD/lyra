import Darwin
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
                let result = makeHandler().start()
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
                let result = makeHandler().start()
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
                let result = makeHandler().start()
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
                let result = makeHandler().start()
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
                let result = makeHandler().start()
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
                let result = makeHandler().stop()
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
                let result = makeHandler().stop()
                guard case .success(.notRunning) = result else {
                    Issue.record("Expected .notRunning")
                    return
                }
            }
            #expect(spy.releaseLockCalled)
        }

        @Test("stops after TERM when process exits cleanly")
        func stopsAfterTerm() {
            let spy = SpyProcessGateway(
                overlayPIDs: [42],
                locked: true,
                runningResponses: [42: [false, false]]
            )
            withDependencies {
                $0.processGateway = spy
            } operation: {
                let result = makeHandler().stop()
                #expect(result == .success(.stopped))
            }
            #expect(spy.sentSignals == [.init(pid: 42, signal: SIGTERM)])
            #expect(spy.releaseLockCalled)
        }

        @Test("falls back to KILL when TERM does not stop the process")
        func escalatesToKill() {
            let spy = SpyProcessGateway(
                overlayPIDs: [42],
                locked: true,
                runningResponses: [42: Array(repeating: true, count: 21)]
            )
            withDependencies {
                $0.processGateway = spy
            } operation: {
                let result = makeHandler().stop()
                #expect(result == .success(.stopped))
            }
            #expect(spy.sentSignals == [.init(pid: 42, signal: SIGTERM), .init(pid: 42, signal: SIGKILL)])
            #expect(spy.releaseLockCalled)
        }

        @Test("fails when lock never releases after stopping")
        func lockReleaseTimesOut() {
            let spy = SpyProcessGateway(
                overlayPIDs: [42],
                locked: true,
                runningResponses: [42: [false, false]],
                releaseClearsLock: false
            )
            withDependencies {
                $0.processGateway = spy
            } operation: {
                let result = makeHandler().stop()
                #expect(result == .failure(.lockReleaseTimedOut))
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
                let result = makeHandler().restart()
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
                #expect(makeHandler().acquireDaemonLock())
            }
        }

        @Test("returns false when lock fails")
        func fails() {
            withDependencies {
                $0.processGateway = StubProcessGateway(acquireResult: false)
            } operation: {
                #expect(!makeHandler().acquireDaemonLock())
            }
        }
    }
}

private func makeHandler() -> ProcessHandlerImpl {
    ProcessHandlerImpl(
        startupDelayMicroseconds: 0,
        pollDelayMicroseconds: 0,
        maxPollingAttempts: 20,
        sleepMicroseconds: { _ in }
    )
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
    struct SignalCall: Equatable {
        let pid: Int32
        let signal: Int32
    }

    let overlayPIDsValue: [Int32]
    var locked: Bool
    private let releaseClearsLock: Bool
    private var runningResponses: [Int32: [Bool]]
    private(set) var releaseLockCalled = false
    private(set) var sentSignals: [SignalCall] = []

    init(
        overlayPIDs: [Int32] = [],
        locked: Bool = false,
        runningResponses: [Int32: [Bool]] = [:],
        releaseClearsLock: Bool = true
    ) {
        self.overlayPIDsValue = overlayPIDs
        self.locked = locked
        self.runningResponses = runningResponses
        self.releaseClearsLock = releaseClearsLock
    }

    var resourceSnapshot: ResourceSnapshot { .init(cpuUser: 0, cpuSystem: 0, peakRSS: 0, currentRSS: 0) }
    var overlayPIDs: [Int32] { overlayPIDsValue }
    func spawnDaemon(executablePath: String) -> Int32? { nil }
    func sendSignal(_ pid: Int32, signal: Int32) -> Bool {
        sentSignals.append(.init(pid: pid, signal: signal))
        return true
    }
    func isRunning(_ pid: Int32) -> Bool {
        guard var responses = runningResponses[pid], let next = responses.first else { return false }
        responses.removeFirst()
        runningResponses[pid] = responses
        return next
    }
    func acquireLock() -> Bool { false }
    var isLocked: Bool { locked }
    func releaseLock() {
        releaseLockCalled = true
        if releaseClearsLock {
            locked = false
        }
    }
    func runLaunchctl(_ arguments: [String]) -> Int32 { 0 }
    func findExecutable(_ name: String) -> String? { nil }
    func run(executable: String, arguments: [String]) -> Int32 { 0 }
    func runCapturingOutput(executable: String, arguments: [String]) -> String? { nil }
    func runStreaming(executable: String, arguments: [String]) -> AsyncStream<String> {
        AsyncStream { $0.finish() }
    }
}
