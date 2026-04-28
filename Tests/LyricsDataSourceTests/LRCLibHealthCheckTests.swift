import Domain
import Foundation
@preconcurrency import Papyrus
import Testing

@testable import LyricsDataSource

@Suite("LRCLibHealthCheck")
struct LRCLibHealthCheckTests {
    @Test("serviceName is LRCLIB API")
    func serviceName() {
        #expect(LRCLibHealthCheck().serviceName == "LRCLIB API")
    }

    @Test("healthCheck passes for 2xx responses")
    func healthCheckPasses() async {
        let check = LRCLibHealthCheck {
            _ = [LyricsResult]()
        }

        let result = await check.healthCheck()

        #expect(result.status == .pass)
        #expect(result.detail.contains("reachable ("))
        #expect(result.latency != nil)
    }

    @Test("healthCheck reports HTTP failures")
    func healthCheckHTTPFailure() async {
        let check = LRCLibHealthCheck {
            throw PapyrusError(
                "request failed",
                URLRequest(url: URL(string: "https://lrclib.net/api/search?q=test")!),
                TestResponse(
                    request: URLRequest(url: URL(string: "https://lrclib.net/api/search?q=test")!),
                    statusCode: 503,
                    body: Data()
                )
            )
        }

        let result = await check.healthCheck()

        #expect(result.status == .fail)
        #expect(result.detail == "HTTP 503")
        #expect(result.latency != nil)
    }

    @Test("healthCheck reports non-HTTP response as HTTP -1")
    func healthCheckNonHTTPResponse() async {
        let check = LRCLibHealthCheck {
            throw PapyrusError(
                "request failed",
                URLRequest(url: URL(string: "https://lrclib.net/api/search?q=test")!),
                NonHTTPPapyrusResponse()
            )
        }

        let result = await check.healthCheck()

        #expect(result.status == .fail)
        #expect(result.detail == "HTTP -1")
    }

    @Test("healthCheck reports request errors")
    func healthCheckError() async {
        let check = LRCLibHealthCheck {
            throw StubError("stubbed request failure")
        }

        let result = await check.healthCheck()

        #expect(result.status == .fail)
        #expect(result.detail == "stubbed request failure")
        #expect(result.latency == nil)
    }

    @Test("healthCheck reports HTTP failures from PapyrusError response")
    func healthCheckPapyrusErrorWithResponse() async {
        let check = LRCLibHealthCheck {
            throw PapyrusError(
                "request failed",
                URLRequest(url: URL(string: "https://lrclib.net/api/search?q=test")!),
                TestResponse(
                    request: URLRequest(url: URL(string: "https://lrclib.net/api/search?q=test")!),
                    statusCode: 429,
                    body: Data()
                )
            )
        }

        let result = await check.healthCheck()

        #expect(result.status == .fail)
        #expect(result.detail == "HTTP 429")
        #expect(result.latency != nil)
    }
}

private struct NonHTTPPapyrusResponse: Response {
    let request: Request? = nil
    let statusCode: Int? = nil
    let body: Data? = nil
    let headers: [String: String]? = nil
    let error: Error? = nil
}
