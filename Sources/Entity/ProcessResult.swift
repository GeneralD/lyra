public typealias StartResult = Result<StartSuccess, StartFailure>
public typealias StopResult = Result<StopSuccess, StopFailure>

public enum StartSuccess: Sendable, Equatable {
    case started(pid: Int32)
}

public enum StartFailure: Error, Sendable, Equatable {
    case alreadyRunning
    case daemonExitedImmediately
    case spawnFailed(detail: String)
}

public enum StopSuccess: Sendable, Equatable {
    case stopped
    case notRunning
}

public enum StopFailure: Error, Sendable, Equatable {
    case lockReleaseTimedOut
}
