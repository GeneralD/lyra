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

import Alamofire
import Domain
import Foundation

public struct MusicBrainzMetadataDataSourceImpl {
    public init() {}
}

extension MusicBrainzMetadataDataSourceImpl: Sendable {}

extension MusicBrainzMetadataDataSourceImpl: MetadataDataSource {
    public func resolve(track: Track) async -> [MusicBrainzMetadata] {
        let regex = RegexMetadataDataSourceImpl()
        let parsed = regex.parseArtistTitle(track.title)
        let normalized = parsed.title
        let normalizedArtist = regex.normalizeArtist(parsed.artist ?? track.artist)

        for query: MusicBrainzAPI in [
            .searchRecording(title: normalized, artist: normalizedArtist, duration: nil),
            .searchRecording(title: normalized, artist: nil, duration: nil),
        ] {
            guard let response: MusicBrainzResponse = await musicbrainz(query) else { continue }
            let candidates = matchRecordings(from: response, regex: regex)
            guard !candidates.isEmpty else { continue }
            return candidates
        }

        return []
    }
}

extension MusicBrainzMetadataDataSourceImpl {
    fileprivate func matchRecordings(from response: MusicBrainzResponse, regex: RegexMetadataDataSourceImpl) -> [MusicBrainzMetadata] {
        var candidates: [MusicBrainzMetadata] = []
        for recording in response.recordings {
            guard let artistName = recording.artistName else { continue }
            var seen = Set<String>()
            let titles = [recording.title, regex.normalize(recording.title), regex.stripBrackets(recording.title)]
                .filter { seen.insert($0).inserted }
            for t in titles {
                candidates.append(
                    MusicBrainzMetadata(
                        title: t, artist: artistName,
                        duration: recording.duration, musicbrainzId: recording.id
                    ))
            }
        }
        return candidates
    }

    fileprivate func musicbrainz<T: Decodable & Sendable>(_ api: MusicBrainzAPI) async -> T? {
        await AF.request(api)
            .validate(statusCode: 200..<300)
            .serializingDecodable(T.self)
            .response.value
    }
}