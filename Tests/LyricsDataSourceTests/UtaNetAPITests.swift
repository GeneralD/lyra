import Foundation
import Testing
import os

@testable import LyricsDataSource

/// URL-construction tests: verify that `UtaNetAPI` produces the expected
/// `URLRequest` for each page by injecting a fetch closure that records the
/// outgoing request (the URLSession-direct analogue of `TestHTTPService`).
@Suite("UtaNetAPI URL construction")
struct UtaNetAPITests {
    private final class RequestRecorder: Sendable {
        private let storage = OSAllocatedUnfairLock<URLRequest?>(initialState: nil)

        var captured: URLRequest? {
            storage.withLock { $0 }
        }

        func record(_ request: URLRequest) {
            storage.withLock { $0 = request }
        }
    }

    private func makeAPI(
        status: Int = 200,
        body: Data = Data("<html></html>".utf8),
        recorder: RequestRecorder
    ) -> UtaNetAPI {
        UtaNetAPI(baseURL: UtaNetAPI.baseURL) { request in
            recorder.record(request)
            let response = HTTPURLResponse(
                url: request.url ?? URL(fileURLWithPath: "/"),
                statusCode: status, httpVersion: nil, headerFields: nil
            )
            guard let response else { throw StubError("could not build response") }
            return (body, response)
        }
    }

    @Test("searchSongs builds the title-search URL with an encoded keyword")
    func searchSongsURL() async throws {
        let recorder = RequestRecorder()
        let api = makeAPI(recorder: recorder)

        _ = try await api.searchSongs(keyword: "夜に駆ける")
        let url = recorder.captured?.url?.absoluteString ?? ""

        #expect(url.hasPrefix("https://www.uta-net.com/search/?"))
        #expect(url.contains("Aselect=2"))
        #expect(url.contains("Bselect=3"))
        #expect(url.contains("Keyword=%E5%A4%9C%E3%81%AB%E9%A7%86%E3%81%91%E3%82%8B"))
    }

    @Test("lyricsPage builds the song URL from the id")
    func lyricsPageURL() async throws {
        let recorder = RequestRecorder()
        let api = makeAPI(recorder: recorder)

        _ = try await api.lyricsPage(songID: 284_748)

        #expect(recorder.captured?.url?.absoluteString == "https://www.uta-net.com/song/284748/")
    }

    @Test("requests carry a browser-like User-Agent to pass Cloudflare")
    func userAgentHeader() async throws {
        let recorder = RequestRecorder()
        let api = makeAPI(recorder: recorder)

        _ = try await api.searchSongs(keyword: "test")
        let userAgent = recorder.captured?.value(forHTTPHeaderField: "User-Agent") ?? ""

        #expect(userAgent.hasPrefix("Mozilla/5.0"))
        #expect(userAgent.contains("Safari"))
    }

    @Test("non-2xx status throws httpStatus")
    func non2xxThrows() async {
        let recorder = RequestRecorder()
        let api = makeAPI(status: 403, recorder: recorder)

        await #expect(throws: UtaNetError.httpStatus(403)) {
            _ = try await api.searchSongs(keyword: "test")
        }
    }

    @Test("non-UTF-8 body throws notUTF8")
    func nonUTF8Throws() async {
        let recorder = RequestRecorder()
        let api = makeAPI(body: Data([0xFF, 0xFE, 0x80]), recorder: recorder)

        await #expect(throws: UtaNetError.notUTF8) {
            _ = try await api.lyricsPage(songID: 1)
        }
    }

    @Test("2xx response returns the body as a string")
    func returnsBody() async throws {
        let recorder = RequestRecorder()
        let api = makeAPI(body: Data("<html>ok</html>".utf8), recorder: recorder)

        let html = try await api.lyricsPage(songID: 1)

        #expect(html == "<html>ok</html>")
    }
}
