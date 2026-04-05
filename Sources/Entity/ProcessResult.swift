public enum StartResult: Sendable {
    case started(pid: Int32)
    case alreadyRunning
    case daemonExitedImmediately
    case spawnFailed(detail: String)

    public var message: String {
        switch self {
        case .started(let pid): "Overlay started (PID \(pid))"
        case .alreadyRunning: "Already running"
        case .daemonExitedImmediately: "Failed to start (daemon exited immediately)"
        case .spawnFailed(let detail): "Failed to start: \(detail)"
        }
    }

    public var succeeded: Bool {
        guard case .started = self else { return false }
        return true
    }
}

public enum StopResult: Sendable, Equatable {
    case stopped
    case notRunning
    case lockReleaseTimedOut

    public var message: String {
        switch self {
        case .stopped: "Stopped"
        case .notRunning: "Not running"
        case .lockReleaseTimedOut: "Stopped (warning: lock release timed out)"
        }
    }

    public var succeeded: Bool { self != .lockReleaseTimedOut }
}
