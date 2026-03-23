import Domain
import Foundation
import Testing

@testable import LyricsDataSource

@Suite("LyricsDataSource")
struct LyricsDataSourceTests {

    @Test("LRCLibAPI.get builds correct URL with title, artist, and duration")
    func getEndpointConstruction() throws {
        let api = LRCLibAPI.get(title: "Numb", artist: "Linkin Park", duration: 187)
        let request = try api.asURLRequest()
        let url = request.url!.absoluteString
        #expect(url.contains("lrclib.net/api/get"))
        #expect(url.contains("track_name=Numb"))
        #expect(url.contains("artist_name=Linkin%20Park"))
        #expect(url.contains("duration=187"))
    }

    @Test("LRCLibAPI.get omits duration when nil")
    func getEndpointWithoutDuration() throws {
        let api = LRCLibAPI.get(title: "Song", artist: "Artist", duration: nil)
        let request = try api.asURLRequest()
        let url = request.url!.absoluteString
        #expect(!url.contains("duration"))
    }

    @Test("LRCLibAPI.search builds correct URL with query")
    func searchEndpointConstruction() throws {
        let api = LRCLibAPI.search(query: "hello world")
        let request = try api.asURLRequest()
        let url = request.url!.absoluteString
        #expect(url.contains("lrclib.net/api/search"))
        #expect(url.contains("q=hello%20world"))
    }

    @Test("LRCLibAPI sets User-Agent header")
    func userAgentHeader() throws {
        let api = LRCLibAPI.get(title: "T", artist: "A", duration: nil)
        let request = try api.asURLRequest()
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "lyra (https://github.com/GeneralD/lyra)")
    }

    @Test("LRCLibAPI uses GET method")
    func httpMethod() throws {
        let api = LRCLibAPI.search(query: "test")
        let request = try api.asURLRequest()
        #expect(request.httpMethod == "GET")
    }
}
