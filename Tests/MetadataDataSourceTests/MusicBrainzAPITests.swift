import Foundation
@preconcurrency import Papyrus
import Testing

@testable import MetadataDataSource

@Suite("MusicBrainzAPI URL construction")
struct MusicBrainzAPITests {
    private func makeAPI(_ recorder: TestHTTPService) -> any MusicBrainz {
        MusicBrainzAPI(provider: Provider(baseURL: MusicBrainzAPI.baseURL, http: recorder))
    }

    @Test("builds GET request with path and User-Agent")
    func requestBasics() async {
        let recorder = TestHTTPService()
        let api = makeAPI(recorder)
        let query = MusicBrainzAPI.luceneQuery(title: "Song", artist: nil, duration: nil)

        _ = try? await api.searchRecording(query: query, fmt: "json", limit: 5)
        let captured = recorder.captured

        #expect(captured?.httpMethod == "GET")
        #expect(captured?.url?.scheme == "https")
        #expect(captured?.url?.host == "musicbrainz.org")
        #expect(captured?.url?.path == "/ws/2/recording")
        #expect(captured?.value(forHTTPHeaderField: "User-Agent") == "lyra (https://github.com/GeneralD/lyra)")
    }

    @Test("encodes title-only query with default params")
    func titleOnlyQuery() async {
        let recorder = TestHTTPService()
        let api = makeAPI(recorder)
        let query = MusicBrainzAPI.luceneQuery(title: "Brave Shine", artist: nil, duration: nil)

        _ = try? await api.searchRecording(query: query, fmt: "json", limit: 5)
        let url = try? #require(recorder.captured?.url)
        let components = URLComponents(url: url ?? URL(string: "about:blank")!, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []

        #expect(items.first(where: { $0.name == "query" })?.value == "\"Brave Shine\"")
        #expect(items.first(where: { $0.name == "fmt" })?.value == "json")
        #expect(items.first(where: { $0.name == "limit" })?.value == "5")
    }

    @Test("healthCheck builds fixed search request")
    func healthCheckRequest() async {
        let recorder = TestHTTPService(body: Data())
        let api = makeAPI(recorder)

        _ = try? await api.healthCheck()
        let url = recorder.captured?.url
        let components = URLComponents(url: url ?? URL(string: "about:blank")!, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []

        #expect(url?.path == "/ws/2/recording")
        #expect(items.first(where: { $0.name == "query" })?.value == "test")
        #expect(items.first(where: { $0.name == "fmt" })?.value == "json")
        #expect(items.first(where: { $0.name == "limit" })?.value == "1")
        #expect(recorder.captured?.httpMethod == "GET")
    }

    @Test("luceneQuery composes title-only filter")
    func luceneTitleOnly() {
        let q = MusicBrainzAPI.luceneQuery(title: "Brave Shine", artist: nil, duration: nil)
        #expect(q == "\"Brave Shine\"")
    }

    @Test("luceneQuery adds artist filter when artist is provided")
    func luceneArtistFilter() {
        let q = MusicBrainzAPI.luceneQuery(title: "Brave Shine", artist: "Aimer", duration: nil)
        #expect(q == "\"Brave Shine\" AND artist:\"Aimer\"")
    }

    @Test("luceneQuery adds duration window in milliseconds")
    func luceneDurationWindow() {
        let q = MusicBrainzAPI.luceneQuery(title: "Brave Shine", artist: "Aimer", duration: 225)
        #expect(q == "\"Brave Shine\" AND artist:\"Aimer\" AND dur:[210000 TO 240000]")
    }

    @Test("luceneQuery composes title + duration without artist")
    func luceneTitleDuration() {
        let q = MusicBrainzAPI.luceneQuery(title: "Song", artist: nil, duration: 60)
        #expect(q == "\"Song\" AND dur:[45000 TO 75000]")
    }
}
