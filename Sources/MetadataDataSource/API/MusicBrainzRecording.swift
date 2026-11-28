import Foundation

public struct MusicBrainzRecording: Sendable {
    public let id: String
    public let title: String
    public let length: Int?
    public let artistCredit: [ArtistCredit]?

    public var artistName: String? {
        artistCredit?.first?.name
    }

    public var duration: TimeInterval? {
        length.map { TimeInterval($0) / 1000 }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, length
        case artistCredit = "artist-credit"
    }
}

extension MusicBrainzRecording: Decodable {}
