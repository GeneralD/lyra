import Domain

struct TrackIdentity: Equatable {
    let title: String?
    let artist: String?

    init(_ nowPlaying: NowPlaying) {
        title = nowPlaying.title
        artist =
            if let artist = nowPlaying.artist, !artist.isEmpty {
                artist
            } else {
                nil
            }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        guard let lhsArtist = lhs.artist, let rhsArtist = rhs.artist else {
            return lhs.title == rhs.title
        }
        return lhs.title == rhs.title && lhsArtist == rhsArtist
    }
}
