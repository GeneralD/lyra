import Domain
import Foundation

public struct ProcessHandlerImpl: ProcessHandler {
    private let lock: ProcessLockable
    private let processManager: ProcessManaging

    public init(lock: ProcessLockable, processManager: ProcessManaging) {
        self.lock = lock
        self.processManager = processManager
    }

    public func start() -> StartResult {
        guard !lock.isLocked, processManager.findOverlayPIDs().isEmpty else {
            return .failure(.alreadyRunning)
        }

        let executablePath = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executablePath)
        task.arguments = ["daemon"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else {
            return .failure(.spawnFailed(detail: "Failed to launch daemon process"))
        }

        usleep(500_000)
        guard task.isRunning else { return .failure(.daemonExitedImmediately) }
        return .success(.started(pid: task.processIdentifier))
    }

    public func stop() -> StopResult {
        let pids = processManager.findOverlayPIDs()
        guard !pids.isEmpty else {
            guard lock.isLocked else { return .success(.notRunning) }
            lock.cleanup()
            return .success(.notRunning)
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
            guard lock.isLocked else { return .success(.stopped) }
            usleep(100_000)
        }
        return lock.isLocked ? .failure(.lockReleaseTimedOut) : .success(.stopped)
    }

    public func restart() -> StartResult {
        guard case .success = stop() else { return .failure(.alreadyRunning) }
        return start()
    }

    public func acquireDaemonLock() -> Bool {
        lock.acquire()
    }
}
