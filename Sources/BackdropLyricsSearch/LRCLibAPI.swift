import Alamofire
import Foundation

enum LRCLibAPI {
    case get(title: String, artist: String, duration: TimeInterval?)
    case search(query: String)
}

extension LRCLibAPI: URLRequestConvertible {
    func asURLRequest() throws -> URLRequest {
        var request = try URLRequest(url: baseURL + path, method: .get)
        request.setValue("now-playing/1.0", forHTTPHeaderField: "User-Agent")
        return try URLEncoding.default.encode(request, with: parameters)
    }
}

private extension LRCLibAPI {
    var baseURL: String { "https://lrclib.net/api" }

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
