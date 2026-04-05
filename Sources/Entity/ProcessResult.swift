public enum StartResult: Sendable {
    case started(pid: Int32)
    case alreadyRunning
    case daemonExitedImmediately

    public var message: String {
        switch self {
        case .started(let pid): "Overlay started (PID \(pid))"
        case .alreadyRunning: "Already running"
        case .daemonExitedImmediately: "Failed to start (daemon exited immediately)"
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
}
