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
