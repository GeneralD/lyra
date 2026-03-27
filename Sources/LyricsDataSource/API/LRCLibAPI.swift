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

public enum LRCLibAPI {
    case get(title: String, artist: String, duration: TimeInterval?)
    case search(query: String)
}

extension LRCLibAPI: URLRequestConvertible {
    public func asURLRequest() throws -> URLRequest {
        var request = try URLRequest(url: Self.baseURL + path, method: .get)
        request.setValue("lyra (https://github.com/GeneralD/lyra)", forHTTPHeaderField: "User-Agent")
        return try URLEncoding.default.encode(request, with: parameters)
    }
}

extension LRCLibAPI {
    static let baseURL = "https://lrclib.net/api"

    var path: String {
        switch self {
        case .get: "/get"
        case .search: "/search"
        }
    }

    var parameters: [String: String] {
        switch self {
        case .get(let title, let artist, let duration):
            var params = ["track_name": title, "artist_name": artist]
            if let duration { params["duration"] = String(Int(duration)) }
            return params
        case .search(let query):
            return ["q": query]
        }
    }
}