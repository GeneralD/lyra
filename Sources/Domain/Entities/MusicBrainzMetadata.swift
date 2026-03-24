import Foundation

public struct MusicBrainzMetadata: Sendable {
    public let title: String
    public let artist: String
    public let duration: TimeInterval?
    public let musicbrainzId: String

    public init(title: String, artist: String, duration: TimeInterval?, musicbrainzId: String) {
        self.title = title
        self.artist = artist
        self.duration = duration
        self.musicbrainzId = musicbrainzId
    }
}
