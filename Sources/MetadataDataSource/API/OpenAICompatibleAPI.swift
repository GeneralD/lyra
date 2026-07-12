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
    /// Builds the auth-attaching Provider. The session comes from the caller's
    /// `ScopedAPISession` in production (#318); the `nil` default gives a
    /// throwaway ephemeral session for construction-only tests that never make a
    /// network call.
    public static func provider(for config: AIEndpoint, urlSession: URLSession? = nil) -> Provider {
        let endpoint =
            config.endpoint.hasSuffix("/")
            ? String(config.endpoint.dropLast())
            : config.endpoint
        return Provider(baseURL: endpoint, urlSession: urlSession ?? URLSession(configuration: .ephemeral)).modifyRequests { req in
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
