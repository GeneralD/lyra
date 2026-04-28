import Domain
import Foundation
@preconcurrency import Papyrus
import Testing

@testable import LyricsDataSource

/// URL-construction tests: verify that `LRCLibAPI` (Papyrus-generated)
/// produces the expected `URLRequest` for each endpoint by injecting a
/// custom `HTTPService` that records the outgoing request.
@Suite("LRCLibAPI URL construction")
struct LRCLibAPIURLConstructionTests {
    private func makeAPI(_ recorder: TestHTTPService) -> any LRCLib {
        LRCLibAPI(provider: Provider(baseURL: "https://lrclib.net", http: recorder))
    }

    @Test("get builds correct URL with title, artist, and duration")
    func getEndpointConstruction() async throws {
        let recorder = TestHTTPService()
        let api = makeAPI(recorder)

        _ = try await api.get(trackName: "Numb", artistName: "Linkin Park", duration: 187)
        let url = recorder.captured?.url?.absoluteString ?? ""

        #expect(url.contains("lrclib.net/api/get"))
        #expect(url.contains("track_name=Numb"))
        #expect(url.contains("artist_name=Linkin%20Park"))
        #expect(url.contains("duration=187"))
    }

    @Test("get omits duration when nil")
    func getEndpointWithoutDuration() async throws {
        let recorder = TestHTTPService()
        let api = makeAPI(recorder)

        _ = try await api.get(trackName: "Song", artistName: "Artist", duration: nil)
        let url = recorder.captured?.url?.absoluteString ?? ""

        #expect(!url.contains("duration"))
    }

    @Test("search builds correct URL with query")
    func searchEndpointConstruction() async throws {
        let recorder = TestHTTPService(body: Data("[]".utf8))
        let api = LRCLibAPI(provider: Provider(baseURL: "https://lrclib.net", http: recorder))

        _ = try await api.search(q: "hello world")
        let url = recorder.captured?.url?.absoluteString ?? ""

        #expect(url.contains("lrclib.net/api/search"))
        #expect(url.contains("q=hello%20world"))
    }

    @Test("requests carry the User-Agent header")
    func userAgentHeader() async throws {
        let recorder = TestHTTPService()
        let api = makeAPI(recorder)

        _ = try await api.get(trackName: "T", artistName: "A", duration: nil)

        #expect(recorder.captured?.value(forHTTPHeaderField: "User-Agent") == "lyra (https://github.com/GeneralD/lyra)")
    }

    @Test("get and search use HTTP GET")
    func httpMethod() async throws {
        let searchRecorder = TestHTTPService(body: Data("[]".utf8))
        let searchAPI = LRCLibAPI(provider: Provider(baseURL: "https://lrclib.net", http: searchRecorder))
        _ = try await searchAPI.search(q: "test")
        #expect(searchRecorder.captured?.httpMethod == "GET")

        let getRecorder = TestHTTPService()
        let getAPI = makeAPI(getRecorder)
        _ = try await getAPI.get(trackName: "x", artistName: "y", duration: nil)
        #expect(getRecorder.captured?.httpMethod == "GET")
    }

    @Test("special characters in query are percent-encoded")
    func specialCharactersEncoded() async throws {
        let recorder = TestHTTPService(body: Data("[]".utf8))
        let api = LRCLibAPI(provider: Provider(baseURL: "https://lrclib.net", http: recorder))

        _ = try await api.search(q: "AC/DC & Friends")
        let url = recorder.captured?.url?.absoluteString ?? ""

        // `&` and `/` must be encoded inside the query value
        #expect(url.contains("q=AC%2FDC%20%26%20Friends"))
    }

    @Test("zero duration is sent (not omitted)")
    func zeroDurationSent() async throws {
        let recorder = TestHTTPService()
        let api = makeAPI(recorder)

        _ = try await api.get(trackName: "x", artistName: "y", duration: 0)
        let url = recorder.captured?.url?.absoluteString ?? ""

        #expect(url.contains("duration=0"))
    }

    @Test("duration is sent as integer seconds, not decimal")
    func durationIsIntegerSeconds() async throws {
        let recorder = TestHTTPService()
        let api = makeAPI(recorder)

        // The DataSource layer truncates Double duration to Int via Int.init.
        // The API protocol now takes Int? to enforce this at the type level.
        _ = try await api.get(trackName: "x", artistName: "y", duration: 225)
        let url = recorder.captured?.url?.absoluteString ?? ""

        #expect(url.contains("duration=225"))
        #expect(!url.contains("duration=225."))
    }
}
