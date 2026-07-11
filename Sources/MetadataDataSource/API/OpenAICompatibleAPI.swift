import Domain
import Foundation
@preconcurrency import Papyrus

@API
@Headers(["Content-Type": "application/json"])
public protocol OpenAICompatible {
    @POST("/chat/completions")
    func chatCompletion(request: Body<ChatCompletionRequest>) async throws -> ChatCompletionResponse
}

extension OpenAICompatible {
    /// Ephemeral session for the same staleness reason as `EphemeralSessionLRCLib`
    /// (#318). The 60 s request timeout matches the `URLSession.shared` default
    /// this call always ran with — kept generous because local LLMs can take
    /// tens of seconds to produce a completion.
    public static func ephemeralSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        return URLSession(configuration: configuration)
    }

    public static func provider(for config: AIEndpoint, urlSession: URLSession? = nil) -> Provider {
        let endpoint =
            config.endpoint.hasSuffix("/")
            ? String(config.endpoint.dropLast())
            : config.endpoint
        return Provider(baseURL: endpoint, urlSession: urlSession ?? ephemeralSession()).modifyRequests { req in
            req.addHeader("Authorization", value: "Bearer \(config.apiKey)")
        }
    }
}

public struct ChatCompletionRequest: Codable, Sendable {
    public let model: String
    public let messages: [Message]
    public let temperature: Double
    public let responseFormat: ResponseFormat

    public init(model: String, messages: [Message], temperature: Double = 0, responseFormat: ResponseFormat = .jsonObject) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.responseFormat = responseFormat
    }

    public struct Message: Codable, Sendable {
        public let role: String
        public let content: String

        public init(role: String, content: String) {
            self.role = role
            self.content = content
        }
    }

    public struct ResponseFormat: Codable, Sendable {
        public let type: String

        public init(type: String) {
            self.type = type
        }

        public static let jsonObject = ResponseFormat(type: "json_object")
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case responseFormat = "response_format"
    }
}
