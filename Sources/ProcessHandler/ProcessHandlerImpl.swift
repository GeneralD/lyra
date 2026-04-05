import Domain
import Foundation

public struct ProcessHandlerImpl: ProcessHandler {
    private let lock: ProcessLockable
    private let processManager: ProcessManaging

    public init(lock: ProcessLockable, processManager: ProcessManaging) {
        self.lock = lock
        self.processManager = processManager
    }

    public func start() throws -> StartResult {
        guard !lock.isLocked, processManager.findOverlayPIDs().isEmpty else {
            return .alreadyRunning
        }

        let executablePath = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executablePath)
        task.arguments = ["daemon"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try task.run()

        usleep(500_000)
        guard task.isRunning else { return .daemonExitedImmediately }
        return .started(pid: task.processIdentifier)
    }

    public func stop() -> StopResult {
        let pids = processManager.findOverlayPIDs()
        guard !pids.isEmpty else {
            // No PID found, but lock may be stale — clean up
            guard lock.isLocked else { return .notRunning }
            lock.cleanup()
            return .notRunning
        }

        for pid in pids { kill(pid, SIGTERM) }
        for _ in 0..<20 {
            guard pids.contains(where: { kill($0, 0) == 0 }) else { break }
            usleep(100_000)
        }
        for pid in pids where kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        usleep(100_000)
        lock.cleanup()

        for _ in 0..<20 {
            guard lock.isLocked else { return .stopped }
            usleep(100_000)
        }
        return lock.isLocked ? .lockReleaseTimedOut : .stopped
    }

    public func restart() throws -> StartResult {
        let stopResult = stop()
        guard stopResult != .lockReleaseTimedOut else { return .alreadyRunning }
        return try start()
    }

    public func acquireDaemonLock() -> Bool {
        lock.acquire()
    }
}
