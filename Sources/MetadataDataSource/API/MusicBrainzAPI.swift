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
import Foundation

public enum MusicBrainzAPI {
    case searchRecording(title: String, artist: String?, duration: TimeInterval?)
}

extension MusicBrainzAPI: URLRequestConvertible {
    public func asURLRequest() throws -> URLRequest {
        var request = try URLRequest(url: Self.baseURL + path, method: .get)
        request.setValue("lyra (https://github.com/GeneralD/lyra)", forHTTPHeaderField: "User-Agent")
        return try URLEncoding.default.encode(request, with: parameters)
    }
}

extension MusicBrainzAPI {
    static let baseURL = "https://musicbrainz.org/ws/2"

    var path: String {
        switch self {
        case .searchRecording: "/recording"
        }
    }

    var parameters: [String: String] {
        switch self {
        case .searchRecording(let title, let artist, let duration):
            var query = "\"\(title)\""
            if let artist { query += " AND artist:\"\(artist)\"" }
            if let duration {
                let ms = Int(duration * 1000)
                query += " AND dur:[\(ms - 15000) TO \(ms + 15000)]"
            }
            return ["query": query, "fmt": "json", "limit": "5"]
        }
    }
}