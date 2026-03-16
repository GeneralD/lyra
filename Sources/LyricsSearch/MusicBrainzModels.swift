import Foundation

struct MusicBrainzResponse {
    let recordings: [MusicBrainzRecording]
}

extension MusicBrainzResponse: Decodable, Sendable {}

struct MusicBrainzRecording {
    let id: String
    let title: String
    let length: Int?
    let artistCredit: [ArtistCredit]?

    var artistName: String? {
        artistCredit?.first?.name
    }

    var duration: TimeInterval? {
        length.map { TimeInterval($0) / 1000 }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, length
        case artistCredit = "artist-credit"
    }
}

extension MusicBrainzRecording: Decodable, Sendable {}

struct ArtistCredit {
    let name: String
}

extension ArtistCredit: Decodable, Sendable {}
