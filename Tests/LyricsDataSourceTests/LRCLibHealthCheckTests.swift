import Domain
import Foundation
import Testing

@testable import LyricsDataSource

@Suite("LRCLibHealthCheck")
struct LRCLibHealthCheckTests {
    private let api = LRCLibAPI.search(query: "test")

    @Test("healthCheck passes for 2xx responses")
    func healthCheckPasses() async {
        let result = await api.healthCheck { request in
            #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("lyra") == true)
            #expect(request.timeoutInterval == 10)
            #expect(request.url?.absoluteString == "https://lrclib.net/api/search?q=test")
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(), response)
        }

        #expect(result.status == .pass)
        #expect(result.detail.contains("reachable ("))
        #expect(result.latency != nil)
    }

    @Test("healthCheck reports HTTP failures")
    func healthCheckHTTPFailure() async {
        let result = await api.healthCheck { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 503,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(), response)
        }

        #expect(result.status == .fail)
        #expect(result.detail == "HTTP 503")
        #expect(result.latency != nil)
    }

    @Test("healthCheck reports non-HTTP response as HTTP -1")
    func healthCheckNonHTTPResponse() async {
        let result = await api.healthCheck { request in
            let response = URLResponse(
                url: try #require(request.url),
                mimeType: nil, expectedContentLength: 0, textEncodingName: nil
            )
            return (Data(), response)
        }

        #expect(result.status == .fail)
        #expect(result.detail == "HTTP -1")
    }

    @Test("healthCheck reports request errors")
    func healthCheckError() async {
        let result = await api.healthCheck { _ in
            throw LRCLibStubError()
        }

        #expect(result.status == .fail)
        #expect(result.detail == "stubbed request failure")
        #expect(result.latency == nil)
    }
}

private struct LRCLibStubError: Error, LocalizedError, Sendable {
    var errorDescription: String? { "stubbed request failure" }
}
