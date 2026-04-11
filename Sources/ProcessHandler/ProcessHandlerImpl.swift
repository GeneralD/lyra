import Dependencies
import Domain
import Foundation

public struct ProcessHandlerImpl {
    private let startupDelayMicroseconds: UInt32
    private let pollDelayMicroseconds: UInt32
    private let maxPollingAttempts: Int
    private let sleepMicroseconds: @Sendable (UInt32) -> Void

    public init() {
        self.init(
            startupDelayMicroseconds: 500_000,
            pollDelayMicroseconds: 100_000,
            maxPollingAttempts: 20,
            sleepMicroseconds: { microseconds in
                _ = usleep(microseconds)
            }
        )
    }

    init(
        startupDelayMicroseconds: UInt32 = 500_000,
        pollDelayMicroseconds: UInt32 = 100_000,
        maxPollingAttempts: Int = 20,
        sleepMicroseconds: @escaping @Sendable (UInt32) -> Void = { microseconds in
            _ = usleep(microseconds)
        }
    ) {
        self.startupDelayMicroseconds = startupDelayMicroseconds
        self.pollDelayMicroseconds = pollDelayMicroseconds
        self.maxPollingAttempts = maxPollingAttempts
        self.sleepMicroseconds = sleepMicroseconds
    }

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
        sleepMicroseconds(startupDelayMicroseconds)
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
        for _ in 0..<maxPollingAttempts {
            guard pids.contains(where: { gateway.isRunning($0) }) else { break }
            sleepMicroseconds(pollDelayMicroseconds)
        }
        for pid in pids where gateway.isRunning(pid) { _ = gateway.sendSignal(pid, signal: SIGKILL) }
        sleepMicroseconds(pollDelayMicroseconds)
        gateway.releaseLock()

        for _ in 0..<maxPollingAttempts {
            guard gateway.isLocked else { return .success(.stopped) }
            sleepMicroseconds(pollDelayMicroseconds)
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
