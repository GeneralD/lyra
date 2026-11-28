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

    /// Builds the generated client around the auth-attaching `provider(for:)` —
    /// keeps the `X(provider: X.provider(for:))` nesting inside the extension so
    /// call sites name the factory once. Construction performs no I/O.
    public static func api(for config: AIEndpoint, urlSession: URLSession? = nil) -> any OpenAICompatible {
        OpenAICompatibleAPI(provider: provider(for: config, urlSession: urlSession))
    }
}
