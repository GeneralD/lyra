import Alamofire
import Foundation

enum LRCLibAPI {
    case get(title: String, artist: String, duration: TimeInterval?)
    case search(query: String)
}

extension LRCLibAPI: URLRequestConvertible {
    private var baseURL: String { "https://lrclib.net/api" }

    private var path: String {
        switch self {
        case .get: "/get"
        case .search: "/search"
        }
    }

    private var parameters: [String: String] {
        switch self {
        case .get(let title, let artist, let duration):
            var params = ["track_name": title, "artist_name": artist]
            if let duration { params["duration"] = String(Int(duration)) }
            return params
        case .search(let query):
            return ["q": query]
        }
    }

    func asURLRequest() throws -> URLRequest {
        var request = try URLRequest(url: baseURL + path, method: .get)
        request.setValue("now-playing/1.0", forHTTPHeaderField: "User-Agent")
        return try URLEncoding.default.encode(request, with: parameters)
    }
}
