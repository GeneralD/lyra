// Copyright (C) 2026 GeneralD (yumejustice@gmail.com)
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

import Foundation

public struct MusicBrainzResponse: Sendable {
    public let recordings: [MusicBrainzRecording]
}

extension MusicBrainzResponse: Decodable {}

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

public struct ArtistCredit: Sendable {
    public let name: String
}

extension ArtistCredit: Decodable {}