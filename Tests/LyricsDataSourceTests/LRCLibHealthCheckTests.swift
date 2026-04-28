import Domain
import Foundation
import Testing
import os

@testable import LyricsDataSource

@Suite("LRCLibHealthCheck default backend")
struct LRCLibHealthCheckDefaultBackendTests {
    @Test("defaultRequestPerformer invokes URLSession (errors on refused port)")
    func defaultPerformerErrorPath() async {
        // Hitting the refused port forces URLSession.shared.data(for:) to throw,
        // which proves the default closure runs (covers the `try await` line).
        var request = URLRequest(url: URL(string: "http://127.0.0.1:1/")!)
        request.timeoutInterval = 1
        await #expect(throws: (any Error).self) {
            _ = try await LRCLibHealthCheck.defaultRequestPerformer(request)
        }
    }

    @Test("defaultRequestPerformer returns Data + URLResponse on success")
    func defaultPerformerSuccessPath() async throws {
        // Register a URLProtocol mock globally so URLSession.shared (which the
        // default closure binds to) routes through our stub. Each suite uses a
        // unique host suffix so parallel tests don't clobber each other.
        URLProtocolMock.register(host: "lrclib.invalid") { _ in
            (HTTPURLResponse(url: URL(string: "http://lrclib.invalid/")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("ok".utf8))
        }
        // URLProtocol.registerClass is process-global; leave it registered so
        // parallel tests in other suites don't lose interception when this test's
        // defer runs. canInit only matches `.invalid` hosts (RFC 6761 reserved),
        // so production code is never affected.
        URLProtocol.registerClass(URLProtocolMock.self)
        defer { URLProtocolMock.unregister(host: "lrclib.invalid") }

        let (data, response) = try await LRCLibHealthCheck.defaultRequestPerformer(
            URLRequest(url: URL(string: "http://lrclib.invalid/")!)
        )
        #expect(String(data: data, encoding: .utf8) == "ok")
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
    }
}

final class URLProtocolMock: URLProtocol, @unchecked Sendable {
    typealias Responder = @Sendable (URLRequest) -> (HTTPURLResponse, Data)
    private static let lock = OSAllocatedUnfairLock<[String: Responder]>(initialState: [:])

    static func register(host: String, responder: @escaping Responder) {
        lock.withLock { $0[host] = responder }
    }
    static func unregister(host: String) {
        lock.withLock { _ = $0.removeValue(forKey: host) }
    }
    private static func responder(for host: String) -> Responder? {
        lock.withLock { $0[host] }
    }

    /// Only intercept hosts that this class has a registered responder for.
    /// This prevents cross-module URLProtocolMock instances (each test module
    /// has its own copy) from stealing each other's requests.
    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        return responder(for: host) != nil
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let host = request.url?.host, let responder = Self.responder(for: host) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let (response, data) = responder(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite("LRCLibHealthCheck")
struct LRCLibHealthCheckTests {
    @Test("serviceName is LRCLIB API")
    func serviceName() {
        #expect(LRCLibHealthCheck().serviceName == "LRCLIB API")
    }

    @Test("healthCheck passes for 2xx responses")
    func healthCheckPasses() async {
        let check = LRCLibHealthCheck { request in
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

        let result = await check.healthCheck()

        #expect(result.status == .pass)
        #expect(result.detail.contains("reachable ("))
        #expect(result.latency != nil)
    }

    @Test("healthCheck reports HTTP failures")
    func healthCheckHTTPFailure() async {
        let check = LRCLibHealthCheck { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 503,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(), response)
        }

        let result = await check.healthCheck()

        #expect(result.status == .fail)
        #expect(result.detail == "HTTP 503")
        #expect(result.latency != nil)
    }

    @Test("healthCheck reports non-HTTP response as HTTP -1")
    func healthCheckNonHTTPResponse() async {
        let check = LRCLibHealthCheck { request in
            let response = URLResponse(
                url: try #require(request.url),
                mimeType: nil, expectedContentLength: 0, textEncodingName: nil
            )
            return (Data(), response)
        }

        let result = await check.healthCheck()

        #expect(result.status == .fail)
        #expect(result.detail == "HTTP -1")
    }

    @Test("healthCheck reports request errors")
    func healthCheckError() async {
        let check = LRCLibHealthCheck { _ in
            throw StubError("stubbed request failure")
        }

        let result = await check.healthCheck()

        #expect(result.status == .fail)
        #expect(result.detail == "stubbed request failure")
        #expect(result.latency == nil)
    }
}
