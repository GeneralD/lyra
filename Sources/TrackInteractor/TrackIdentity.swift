import Domain

struct TrackIdentity {
    let title: String?
    let artist: String?

    init(_ nowPlaying: NowPlaying) {
        title = nowPlaying.title
        let artist = nowPlaying.artist
        self.artist = artist?.isEmpty == false ? artist : nil
    }
}

extension TrackIdentity: Equatable {
     static func == (lhs: Self, rhs: Self) -> Bool {
        guard let lhsArtist = lhs.artist, let rhsArtist = rhs.artist else {
            return lhs.title == rhs.title
        }
        return lhs.title == rhs.title && lhsArtist == rhsArtist
    }
}
