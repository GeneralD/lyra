import Domain
import Testing

@testable import ProcessHandler

@Suite("ProcessHandlerImpl")
struct ProcessHandlerImplSpec {
    // MARK: - start

    @Suite("start")
    struct Start {
        @Test("returns alreadyRunning when lock is held")
        func lockedReturnsAlreadyRunning() {
            let handler = makeHandler(isLocked: true)
            let result = handler.start()
            guard case .failure(.alreadyRunning) = result else {
                Issue.record("Expected .alreadyRunning")
                return
            }
        }

        @Test("returns alreadyRunning when overlay PIDs exist")
        func pidsReturnsAlreadyRunning() {
            let handler = makeHandler(pids: [12345])
            let result = handler.start()
            guard case .failure(.alreadyRunning) = result else {
                Issue.record("Expected .alreadyRunning")
                return
            }
        }

        @Test("returns alreadyRunning when both locked and PIDs exist")
        func bothReturnsAlreadyRunning() {
            let handler = makeHandler(isLocked: true, pids: [12345])
            let result = handler.start()
            guard case .failure(.alreadyRunning) = result else {
                Issue.record("Expected .alreadyRunning")
                return
            }
        }
    }

    // MARK: - stop

    @Suite("stop")
    struct Stop {
        @Test("returns notRunning when no PIDs and lock is free")
        func noPidsNoLock() {
            let handler = makeHandler()
            let result = handler.stop()
            guard case .success(.notRunning) = result else {
                Issue.record("Expected .notRunning")
                return
            }
        }

        @Test("cleans up stale lock when no PIDs but lock is held")
        func staleLock() {
            let lock = MockLock(locked: true)
            let handler = ProcessHandlerImpl(lock: lock, processManager: MockProcessManager())
            let result = handler.stop()
            guard case .success(.notRunning) = result else {
                Issue.record("Expected .notRunning")
                return
            }
            #expect(lock.cleanupCalled)
        }
    }

    // MARK: - restart

    @Suite("restart")
    struct Restart {
        @Test("returns stopFailed when stop fails")
        func stopFails() {
            let lock = MockLock(locked: true, releaseOnCleanup: false)
            let handler = ProcessHandlerImpl(
                lock: lock,
                processManager: MockProcessManager(pids: [Int32.max])
            )
            let result = handler.restart()
            guard case .failure(.stopFailed) = result else {
                Issue.record("Expected .stopFailed, got \(result)")
                return
            }
        }
    }

    // MARK: - acquireDaemonLock

    @Suite("acquireDaemonLock")
    struct AcquireDaemonLock {
        @Test("delegates to lock.acquire")
        func delegates() {
            let lock = MockLock(acquireResult: true)
            let handler = ProcessHandlerImpl(lock: lock, processManager: MockProcessManager())
            #expect(handler.acquireDaemonLock())
        }

        @Test("returns false when lock fails")
        func fails() {
            let lock = MockLock(acquireResult: false)
            let handler = ProcessHandlerImpl(lock: lock, processManager: MockProcessManager())
            #expect(!handler.acquireDaemonLock())
        }
    }
}

// MARK: - Helpers

private func makeHandler(
    isLocked: Bool = false,
    pids: [Int32] = []
) -> ProcessHandlerImpl {
    ProcessHandlerImpl(
        lock: MockLock(locked: isLocked),
        processManager: MockProcessManager(pids: pids)
    )
}

private final class MockLock: ProcessLockable, @unchecked Sendable {
    private var _isLocked: Bool
    private let acquireResult: Bool
    private let releaseOnCleanup: Bool
    private(set) var cleanupCalled = false

    init(locked: Bool = false, acquireResult: Bool = false, releaseOnCleanup: Bool = true) {
        _isLocked = locked
        self.acquireResult = acquireResult
        self.releaseOnCleanup = releaseOnCleanup
    }

    func acquire() -> Bool { acquireResult }
    var isLocked: Bool { _isLocked }
    func cleanup() {
        cleanupCalled = true
        if releaseOnCleanup { _isLocked = false }
    }
}

private struct MockProcessManager: ProcessManaging {
    var pids: [Int32] = []
    func findOverlayPIDs() -> [Int32] { pids }
}
