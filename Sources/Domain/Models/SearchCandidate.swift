public struct SearchCandidate {
    public let title: String
    public let artist: String

    public init(title: String, artist: String) {
        self.title = title
        self.artist = artist
    }
}

extension SearchCandidate: Sendable, Equatable {}
