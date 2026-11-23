import Dependencies
import Domain
import Foundation

public struct ProcessHandlerImpl {
    private let startupDelay: Duration
    private let pollDelay: Duration
    private let maxPollingAttempts: Int

    public init(
        startupDelay: Duration = .milliseconds(500),
        pollDelay: Duration = .milliseconds(100),
        maxPollingAttempts: Int = 20
    ) {
        self.startupDelay = startupDelay
        self.pollDelay = pollDelay
        self.maxPollingAttempts = maxPollingAttempts
    }

    @Dependency(\.processGateway) private var gateway
    @Dependency(\.continuousClock) private var clock
}

extension ProcessHandlerImpl: ProcessHandler {
    public func start() async -> StartResult {
        guard !gateway.isLocked, gateway.overlayPIDs.isEmpty else {
            return .failure(.alreadyRunning)
        }

        let executablePath = Bundle.main.executablePath ?? CommandLine.arguments[0]
        guard let pid = gateway.spawnDaemon(executablePath: executablePath) else {
            return .failure(.spawnFailed(detail: "Failed to launch daemon process"))
        }
        try? await clock.sleep(for: startupDelay)
        guard gateway.isRunning(pid) else {
            return .failure(.daemonExitedImmediately)
        }
        return .success(.started(pid: pid))
    }

    public func stop() async -> StopResult {
        let pids = gateway.overlayPIDs
        guard !pids.isEmpty else {
            guard gateway.isLocked else { return .success(.notRunning) }
            gateway.releaseLock()
            return .success(.notRunning)
        }

        for pid in pids { _ = gateway.sendSignal(pid, signal: SIGTERM) }
        for _ in 0..<maxPollingAttempts {
            guard pids.contains(where: { gateway.isRunning($0) }) else { break }
            try? await clock.sleep(for: pollDelay)
        }
        for pid in pids where gateway.isRunning(pid) { _ = gateway.sendSignal(pid, signal: SIGKILL) }
        try? await clock.sleep(for: pollDelay)
        gateway.releaseLock()

        for _ in 0..<maxPollingAttempts {
            guard gateway.isLocked else { return .success(.stopped) }
            try? await clock.sleep(for: pollDelay)
        }
        return gateway.isLocked ? .failure(.lockReleaseTimedOut) : .success(.stopped)
    }

    public func restart() async -> StartResult {
        guard case .success = await stop() else { return .failure(.stopFailed) }
        return await start()
    }

    public func acquireDaemonLock() -> Bool {
        gateway.acquireLock()
    }
}
