import Foundation
@preconcurrency import Papyrus

@API
@Headers(["User-Agent": "lyra (https://github.com/GeneralD/lyra)"])
public protocol MusicBrainz {
    @GET("/ws/2/recording")
    func searchRecording(query: String, fmt: String, limit: Int) async throws -> MusicBrainzResponse

    @GET("/ws/2/recording?query=test&fmt=json&limit=1")
    func healthCheck() async throws -> Response
}

extension MusicBrainz {
    public static var baseURL: String { "https://musicbrainz.org" }

    /// Build the Lucene-style query string used by MusicBrainz.
    public static func luceneQuery(title: String, artist: String?, duration: Double?) -> String {
        let clauses: [String?] = [
            "\"\(luceneEscaped(title))\"",
            artist.map { "artist:\"\(luceneEscaped($0))\"" },
            duration.map {
                let ms = Int($0 * 1000)
                return "dur:[\(ms - 15000) TO \(ms + 15000)]"
            },
        ]

        return clauses.compactMap { $0 }.joined(separator: " AND ")
    }

    private static func luceneEscaped(_ value: String) -> String {
        value.reduce(into: "") { escaped, character in
            switch character {
            case "+", "-", "!", "(", ")", "{", "}", "[", "]", "^", "\"", "~", "*", "?", ":", "\\", "/", "&", "|":
                escaped.append("\\")
            default:
                break
            }
            escaped.append(character)
        }
    }
}
