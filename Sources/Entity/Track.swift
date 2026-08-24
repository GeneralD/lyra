import Foundation

public struct Track {
    public let title: String
    public let artist: String
    public let duration: TimeInterval?

    public init(title: String, artist: String, duration: TimeInterval? = nil) {
        self.title = title
        self.artist = artist
        self.duration = duration
    }

    // The same play under a different title — used to carry the search-normalized title
    // (video decoration and cover credits removed). Callers keep one normalized copy and
    // use it for the query, the validation, and the cache identity alike: a title
    // rewritten only for the query would be re-validated against its raw form and
    // discarded, which is the poisoned-cache shape #326 fixed (#343).
    public func withTitle(_ title: String) -> Track {
        Track(title: title, artist: artist, duration: duration)
    }
}

extension Track: Sendable {}
extension Track: Equatable {}
