public enum StartFailure: Error, Sendable, Equatable {
    case alreadyRunning
    case daemonExitedImmediately
    case spawnFailed(detail: String)
    case stopFailed
}
