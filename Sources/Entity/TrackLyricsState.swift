public enum TrackLyricsState {
    case idle
    case loading
    case resolved
    case notFound
}

extension TrackLyricsState: Sendable {}
extension TrackLyricsState: Equatable {}
