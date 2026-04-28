import Domain
import Foundation
@preconcurrency import Papyrus
import Testing

@testable import MetadataDataSource

@Suite("OpenAICompatibleAPI URL construction")
struct OpenAICompatibleAPITests {
    private let config = AIEndpoint(
        endpoint: "https://api.example.com/",
        model: "gpt-test",
        apiKey: "secret-key"
    )

    private func makeAPI(_ recorder: TestHTTPService) -> any OpenAICompatible {
        OpenAICompatibleAPI(
            provider: Provider(baseURL: config.endpoint, http: recorder).modifyRequests { req in
                req.addHeader("Authorization", value: "Bearer \(self.config.apiKey)")
            })
    }

    @Test("chatCompletion sends POST with Authorization and Content-Type")
    func chatCompletionRequest() async throws {
        let recorder = TestHTTPService()
        let api = makeAPI(recorder)
        let request = ChatCompletionRequest.metadataExtraction(
            model: config.model, rawTitle: "Artist『Song』 Official MV", rawArtist: "Uploader"
        )

        _ = try? await api.chatCompletion(request: request)

        let captured = try #require(recorder.captured)
        let bodyData = try #require(captured.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let messages = try #require(body["messages"] as? [[String: String]])
        let responseFormat = try #require(body["response_format"] as? [String: String])

        #expect(captured.url?.absoluteString.contains("/chat/completions") == true)
        #expect(captured.httpMethod == "POST")
        #expect(captured.value(forHTTPHeaderField: "Authorization") == "Bearer secret-key")
        #expect(captured.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(body["model"] as? String == "gpt-test")
        #expect(messages.count == 2)
        #expect(messages[0]["role"] == "system")
        #expect(messages[0]["content"]?.contains("music metadata expert") == true)
        #expect(messages[1]["role"] == "user")
        #expect(messages[1]["content"]?.contains("Title: Artist『Song』 Official MV") == true)
        #expect(messages[1]["content"]?.contains("Artist: Uploader") == true)
        #expect(messages[1]["content"]?.contains("\"title\": \"...\"") == true)
        #expect(responseFormat["type"] == "json_object")
    }

    @Test("trailing slash in endpoint is normalized")
    func providerNormalizesTrailingSlash() {
        // config.endpoint ends with "/"; the provider factory must strip it
        // so requests don't get a double slash before the path.
        let provider = OpenAICompatibleAPI.provider(for: config)

        #expect(!provider.baseURL.hasSuffix("/"))
        #expect(provider.baseURL == "https://api.example.com")
    }

    @Test("provider attaches Bearer token via modifyRequests")
    func providerAttachesBearer() async {
        let recorder = TestHTTPService()
        let api = OpenAICompatibleAPI(
            provider: Provider(baseURL: "https://api.example.com", http: recorder).modifyRequests { req in
                req.addHeader("Authorization", value: "Bearer xyz")
            })
        let request = ChatCompletionRequest.metadataExtraction(model: "x", rawTitle: "t", rawArtist: "a")

        _ = try? await api.chatCompletion(request: request)

        #expect(recorder.captured?.value(forHTTPHeaderField: "Authorization") == "Bearer xyz")
    }
}
