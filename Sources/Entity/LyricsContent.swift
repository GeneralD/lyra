public enum LyricsContent {
    case timed([LyricLine])
    case plain([String])
}

extension LyricsContent: Sendable {}
extension LyricsContent: Equatable {}
