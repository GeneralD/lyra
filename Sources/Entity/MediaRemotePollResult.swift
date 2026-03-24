public enum MediaRemotePollResult: Sendable {
    case info(NowPlaying)
    case noInfo
    case eof
}
