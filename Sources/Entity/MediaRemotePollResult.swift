public enum MediaRemotePollResult {
    case info(NowPlaying)
    case noInfo
    case eof
}

extension MediaRemotePollResult: Sendable {}
