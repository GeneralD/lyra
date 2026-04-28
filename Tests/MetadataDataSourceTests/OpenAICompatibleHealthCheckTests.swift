import Domain
import Foundation
import Testing

@testable import MetadataDataSource

@Suite("OpenAICompatibleHealthCheck default backend")
struct OpenAICompatibleHealthCheckDefaultBackendTests {
    @Test("defaultRequestPerformer invokes URLSession (errors on refused port)")
    func defaultPerformerErrorPath() async {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:1/")!)
        request.timeoutInterval = 1
        await #expect(throws: (any Error).self) {
            _ = try await OpenAICompatibleHealthCheck.defaultRequestPerformer(request)
        }
    }

    @Test("defaultRequestPerformer returns Data + URLResponse on success")
    func defaultPerformerSuccessPath() async throws {
        URLProtocolMock.register(host: "openai.invalid") { _ in
            (HTTPURLResponse(url: URL(string: "http://openai.invalid/")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }
        URLProtocol.registerClass(URLProtocolMock.self)
        defer { URLProtocolMock.unregister(host: "openai.invalid") }

        let (data, response) = try await OpenAICompatibleHealthCheck.defaultRequestPerformer(
            URLRequest(url: URL(string: "http://openai.invalid/")!)
        )
        #expect(String(data: data, encoding: .utf8) == "{}")
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
    }
}

@Suite("OpenAICompatibleHealthCheck")
struct OpenAICompatibleHealthCheckTests {
    private let config = AIEndpoint(
        endpoint: "https://api.example.com/",
        model: "gpt-test",
        apiKey: "secret-key"
    )

    @Test("serviceName is AI endpoint")
    func serviceName() {
        #expect(OpenAICompatibleHealthCheck(config: config).serviceName == "AI endpoint")
    }

    @Test("healthCheck fails for invalid URL")
    func invalidURL() async {
        let check = OpenAICompatibleHealthCheck(
            config: AIEndpoint(endpoint: "http://[", model: "gpt-test", apiKey: "secret-key")
        )
        let result = await check.healthCheck()

        #expect(result.status == .fail)
        #expect(result.detail == "invalid URL")
        #expect(result.latency == nil)
    }

    @Test("healthCheck passes for 2xx responses with auth header")
    func passes() async {
        let check = OpenAICompatibleHealthCheck(config: config) { request in
            #expect(request.url?.absoluteString == "https://api.example.com/chat/completions")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-key")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (Data(), response)
        }

        let result = await check.healthCheck()

        #expect(result.status == .pass)
        #expect(result.detail.contains("authenticated ("))
        #expect(result.detail.hasSuffix("ms)"))
        #expect(result.latency != nil)
    }

    @Test("healthCheck reports auth failures clearly")
    func authFailure() async {
        let check = OpenAICompatibleHealthCheck(config: config) { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 401, httpVersion: nil, headerFields: nil
            )!
            return (Data(), response)
        }

        let result = await check.healthCheck()

        #expect(result.status == .fail)
        #expect(result.detail == "HTTP 401 — check api_key in [ai]")
    }

    @Test("healthCheck reports 403 as auth failure")
    func forbidden() async {
        let check = OpenAICompatibleHealthCheck(config: config) { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 403, httpVersion: nil, headerFields: nil
            )!
            return (Data(), response)
        }

        let result = await check.healthCheck()

        #expect(result.status == .fail)
        #expect(result.detail == "HTTP 403 — check api_key in [ai]")
    }

    @Test("healthCheck reports generic HTTP failures")
    func httpFailure() async {
        let check = OpenAICompatibleHealthCheck(config: config) { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 500, httpVersion: nil, headerFields: nil
            )!
            return (Data(), response)
        }

        let result = await check.healthCheck()

        #expect(result.status == .fail)
        #expect(result.detail == "HTTP 500")
    }

    @Test("healthCheck fails when response is not HTTP")
    func nonHTTP() async {
        let check = OpenAICompatibleHealthCheck(config: config) { request in
            (Data(), URLResponse(url: try #require(request.url), mimeType: nil, expectedContentLength: 0, textEncodingName: nil))
        }

        let result = await check.healthCheck()

        #expect(result.status == .fail)
        #expect(result.detail == "no HTTP response")
    }

    @Test("healthCheck surfaces request errors")
    func requestError() async {
        let check = OpenAICompatibleHealthCheck(config: config) { _ in
            throw StubError()
        }

        let result = await check.healthCheck()

        #expect(result.status == .fail)
        #expect(result.detail == "stubbed request failure")
        #expect(result.latency == nil)
    }
}
