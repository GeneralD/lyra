import Foundation
import Testing

@testable import MetadataDataSource

@Suite("MusicBrainzAPI")
struct MusicBrainzAPITests {
    @Test("searchRecording builds GET request with path and headers")
    func searchRecordingRequestBasics() throws {
        let api = MusicBrainzAPI.searchRecording(title: "Song", artist: nil, duration: nil)

        let request = try api.asURLRequest()

        #expect(request.httpMethod == "GET")
        #expect(request.url?.scheme == "https")
        #expect(request.url?.host == "musicbrainz.org")
        #expect(request.url?.path == "/ws/2/recording")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "lyra (https://github.com/GeneralD/lyra)")
    }

    @Test("searchRecording encodes title-only query with default params")
    func searchRecordingTitleOnly() throws {
        let api = MusicBrainzAPI.searchRecording(title: "Brave Shine", artist: nil, duration: nil)

        let request = try api.asURLRequest()
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = try #require(components.queryItems)
        let query = try #require(queryItems.first(where: { $0.name == "query" })?.value)

        #expect(query == "\"Brave Shine\"")
        #expect(queryItems.first(where: { $0.name == "fmt" })?.value == "json")
        #expect(queryItems.first(where: { $0.name == "limit" })?.value == "5")
    }

    @Test("searchRecording adds artist filter when artist is provided")
    func searchRecordingArtistFilter() throws {
        let api = MusicBrainzAPI.searchRecording(title: "Brave Shine", artist: "Aimer", duration: nil)

        let request = try api.asURLRequest()
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = try #require(components.queryItems)
        let query = try #require(queryItems.first(where: { $0.name == "query" })?.value)

        #expect(query == "\"Brave Shine\" AND artist:\"Aimer\"")
    }

    @Test("searchRecording adds duration window in milliseconds")
    func searchRecordingDurationWindow() throws {
        let api = MusicBrainzAPI.searchRecording(title: "Brave Shine", artist: "Aimer", duration: 225)

        let request = try api.asURLRequest()
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = try #require(components.queryItems)
        let query = try #require(queryItems.first(where: { $0.name == "query" })?.value)

        #expect(query == "\"Brave Shine\" AND artist:\"Aimer\" AND dur:[210000 TO 240000]")
    }
}
