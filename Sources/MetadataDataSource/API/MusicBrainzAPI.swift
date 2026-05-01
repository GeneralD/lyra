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
        var query = "\"\(title)\""
        if let artist { query += " AND artist:\"\(artist)\"" }
        if let duration {
            let ms = Int(duration * 1000)
            query += " AND dur:[\(ms - 15000) TO \(ms + 15000)]"
        }
        return query
    }
}
