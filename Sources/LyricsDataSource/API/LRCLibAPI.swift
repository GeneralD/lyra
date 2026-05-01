import Domain
import Foundation
@preconcurrency import Papyrus

@API
@KeyMapping(.snakeCase)
@Headers(["User-Agent": "lyra (https://github.com/GeneralD/lyra)"])
public protocol LRCLib {
    @GET("/api/get")
    func get(trackName: String, artistName: String, duration: Int?) async throws -> LyricsResult

    @GET("/api/search")
    func search(q: String) async throws -> [LyricsResult]

    @GET("/api/search?q=test")
    func healthCheck() async throws -> Response
}

extension LRCLib {
    public static var baseURL: String { "https://lrclib.net" }
}
