import Alamofire
import Foundation

enum MusicBrainzAPI {
    case searchRecording(title: String, artist: String?, duration: TimeInterval?)
}

extension MusicBrainzAPI: URLRequestConvertible {
    func asURLRequest() throws -> URLRequest {
        var request = try URLRequest(url: baseURL + path, method: .get)
        request.setValue("lyra/1.0 (https://github.com/GeneralD/lyra)", forHTTPHeaderField: "User-Agent")
        return try URLEncoding.default.encode(request, with: parameters)
    }
}

private extension MusicBrainzAPI {
    var baseURL: String { "https://musicbrainz.org/ws/2" }

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
