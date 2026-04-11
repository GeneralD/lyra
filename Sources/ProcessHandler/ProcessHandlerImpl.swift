import Dependencies
import Domain
import Foundation

public struct ProcessHandlerImpl {
    public init() {}

    @Dependency(\.processGateway) private var gateway
}

extension ProcessHandlerImpl: ProcessHandler {
    public func start() -> StartResult {
        guard !gateway.isLocked, gateway.overlayPIDs.isEmpty else {
            return .failure(.alreadyRunning)
        }

        let executablePath = Bundle.main.executablePath ?? CommandLine.arguments[0]
        guard let pid = gateway.spawnDaemon(executablePath: executablePath) else {
            return .failure(.spawnFailed(detail: "Failed to launch daemon process"))
        }
        usleep(500_000)
        guard gateway.isRunning(pid) else {
            return .failure(.daemonExitedImmediately)
        }
        return .success(.started(pid: pid))
    }

    public func stop() -> StopResult {
        let pids = gateway.overlayPIDs
        guard !pids.isEmpty else {
            guard gateway.isLocked else { return .success(.notRunning) }
            gateway.releaseLock()
            return .success(.notRunning)
        }

        for pid in pids { _ = gateway.sendSignal(pid, signal: SIGTERM) }
        for _ in 0..<20 {
            guard pids.contains(where: { gateway.isRunning($0) }) else { break }
            usleep(100_000)
        }
        for pid in pids where gateway.isRunning(pid) { _ = gateway.sendSignal(pid, signal: SIGKILL) }
        usleep(100_000)
        gateway.releaseLock()

        for _ in 0..<20 {
            guard gateway.isLocked else { return .success(.stopped) }
            usleep(100_000)
        }
        return gateway.isLocked ? .failure(.lockReleaseTimedOut) : .success(.stopped)
    }

    public func restart() -> StartResult {
        guard case .success = stop() else { return .failure(.stopFailed) }
        return start()
    }

    public func acquireDaemonLock() -> Bool {
        gateway.acquireLock()
    }
}
