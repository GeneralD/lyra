import Domain
import Foundation
@preconcurrency import Papyrus

/// A call-scoped OpenAI-compatible client owning a fresh ephemeral `URLSession` (#318).
///
/// Same session strategy as `EphemeralSessionLRCLib`, with the LLM-appropriate
/// 60 s request timeout; `deinit` invalidates the session so per-call sessions
/// don't accumulate in the long-lived daemon.
final class EphemeralSessionOpenAICompatible {
    private let api: any OpenAICompatible
    private let session: URLSession

    convenience init(config: AIEndpoint) {
        let session = OpenAICompatibleAPI.ephemeralSession()
        self.init(
            api: OpenAICompatibleAPI(provider: OpenAICompatibleAPI.provider(for: config, urlSession: session)),
            session: session
        )
    }

    init(api: any OpenAICompatible, session: URLSession) {
        self.api = api
        self.session = session
    }

    deinit {
        session.finishTasksAndInvalidate()
    }
}

extension EphemeralSessionOpenAICompatible: OpenAICompatible {
    func chatCompletion(request: ChatCompletionRequest) async throws -> ChatCompletionResponse {
        try await api.chatCompletion(request: request)
    }
}
