import Domain
import Foundation
import Testing

@testable import MetadataDataSource

@Suite("OpenAICompatibleAPI")
struct OpenAICompatibleAPITests {
    private let config = AIEndpoint(
        endpoint: "https://api.example.com/",
        model: "gpt-test",
        apiKey: "secret-key"
    )

    @Test("chatCompletion builds normalized authenticated request")
    func chatCompletionRequest() throws {
        let api = OpenAICompatibleAPI(config: config)

        let request = try api.chatCompletion(rawTitle: "Artist『Song』 Official MV", rawArtist: "Uploader")
        let headers = try #require(request.allHTTPHeaderFields)
        let bodyData = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let model = try #require(body["model"] as? String)
        let messages = try #require(body["messages"] as? [[String: String]])
        let responseFormat = try #require(body["response_format"] as? [String: String])

        #expect(request.url?.absoluteString == "https://api.example.com/chat/completions")
        #expect(request.httpMethod == "POST")
        #expect(headers["Authorization"] == "Bearer secret-key")
        #expect(headers["Content-Type"] == "application/json")
        #expect(request.timeoutInterval == 10)
        #expect(model == "gpt-test")
        #expect(messages.count == 2)
        #expect(messages[0]["role"] == "system")
        #expect(messages[0]["content"]?.contains("music metadata expert") == true)
        #expect(messages[1]["role"] == "user")
        #expect(messages[1]["content"]?.contains("Title: Artist『Song』 Official MV") == true)
        #expect(messages[1]["content"]?.contains("Artist: Uploader") == true)
        #expect(messages[1]["content"]?.contains("\"title\": \"...\"") == true)
        #expect((body["temperature"] as? Int) == 0)
        #expect(responseFormat["type"] == "json_object")
        #expect(api.normalizedEndpoint == "https://api.example.com")
    }

    @Test("chatCompletion throws for invalid endpoint")
    func chatCompletionInvalidEndpoint() {
        let api = OpenAICompatibleAPI(
            config: AIEndpoint(endpoint: "http://[", model: "gpt-test", apiKey: "secret-key")
        )

        #expect(throws: URLError.self) {
            try api.chatCompletion(rawTitle: "Song", rawArtist: "Artist")
        }
    }

    @Test("healthCheck fails for invalid URL")
    func healthCheckInvalidURL() async {
        let api = OpenAICompatibleAPI(
            config: AIEndpoint(endpoint: "http://[", model: "gpt-test", apiKey: "secret-key")
        )

        let result = await api.healthCheck()
        #expect(result.status == .fail)
        #expect(result.detail == "invalid URL")
        #expect(result.latency == nil)
    }

    @Test("healthCheck passes for 2xx responses")
    func healthCheckPasses() async {
        let api = OpenAICompatibleAPI(config: config) { request in
            #expect(request.url?.absoluteString == "https://api.example.com/chat/completions")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-key")
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(), response)
        }

        let result = await api.healthCheck()
        #expect(result.status == .pass)
        #expect(result.detail.contains("authenticated ("))
        #expect(result.detail.hasSuffix("ms)"))
        #expect(result.latency != nil)
    }

    @Test("healthCheck reports auth failures clearly")
    func healthCheckAuthFailure() async {
        let api = OpenAICompatibleAPI(config: config) { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(), response)
        }

        let result = await api.healthCheck()
        #expect(result.status == .fail)
        #expect(result.detail == "HTTP 401 — check api_key in [ai]")
        #expect(result.latency != nil)
    }

    @Test("healthCheck reports generic HTTP failures")
    func healthCheckHTTPFailure() async {
        let api = OpenAICompatibleAPI(config: config) { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(), response)
        }

        let result = await api.healthCheck()
        #expect(result.status == .fail)
        #expect(result.detail == "HTTP 500")
        #expect(result.latency != nil)
    }

    @Test("healthCheck fails when response is not HTTP")
    func healthCheckNonHTTPResponse() async {
        let api = OpenAICompatibleAPI(config: config) { request in
            (Data(), URLResponse(url: try #require(request.url), mimeType: nil, expectedContentLength: 0, textEncodingName: nil))
        }

        let result = await api.healthCheck()
        #expect(result.status == .fail)
        #expect(result.detail == "no HTTP response")
        #expect(result.latency != nil)
    }

    @Test("healthCheck surfaces request errors")
    func healthCheckRequestError() async {
        let api = OpenAICompatibleAPI(config: config) { _ in
            throw StubError()
        }

        let result = await api.healthCheck()
        #expect(result.status == .fail)
        #expect(result.detail == "stubbed request failure")
        #expect(result.latency == nil)
    }
}

private struct StubError: Error, LocalizedError, Sendable {
    var errorDescription: String? { "stubbed request failure" }
}
