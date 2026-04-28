import Domain
import Foundation
@preconcurrency import Papyrus

@testable import MetadataDataSource

/// Manual mock of `MusicBrainz` protocol.
struct MusicBrainzStub: MusicBrainz, @unchecked Sendable {
    let search: @Sendable (_ query: String, _ fmt: String, _ limit: Int) async throws -> MusicBrainzResponse
    let healthCheckResult: @Sendable () async throws -> Response

    init(
        search: @escaping @Sendable (_ query: String, _ fmt: String, _ limit: Int) async throws -> MusicBrainzResponse = { _, _, _ in
            MusicBrainzResponse(recordings: [])
        },
        healthCheck: @escaping @Sendable () async throws -> Response = {
            TestResponse(
                request: URLRequest(url: URL(string: "https://musicbrainz.org/ws/2/recording?query=test&fmt=json&limit=1")!),
                statusCode: 200,
                body: Data()
            )
        }
    ) {
        self.search = search
        self.healthCheckResult = healthCheck
    }

    func searchRecording(query: String, fmt: String, limit: Int) async throws -> MusicBrainzResponse {
        try await search(query, fmt, limit)
    }

    func healthCheck() async throws -> Response {
        try await healthCheckResult()
    }
}

/// Manual mock of `OpenAICompatible` protocol.
struct OpenAICompatibleStub: OpenAICompatible, @unchecked Sendable {
    let chat: @Sendable (_ request: ChatCompletionRequest) async throws -> ChatCompletionResponse

    init(chat: @escaping @Sendable (_ request: ChatCompletionRequest) async throws -> ChatCompletionResponse) {
        self.chat = chat
    }

    func chatCompletion(request: ChatCompletionRequest) async throws -> ChatCompletionResponse {
        try await chat(request)
    }
}
