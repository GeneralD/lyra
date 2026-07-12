import Dependencies
import Domain
import Foundation
@preconcurrency import Papyrus
import ScopedAPISession

public struct LLMMetadataDataSourceImpl {
    @Dependency(\.configDataSource) private var configDataSource
    private let sessionFactory: @Sendable (AIEndpoint) -> ScopedAPISession<any OpenAICompatible>

    public init() {
        self.init(sessionFactory: { config in
            ScopedAPISession(timeout: 60) {
                OpenAICompatibleAPI(provider: OpenAICompatibleAPI.provider(for: config, urlSession: $0))
            }
        })
    }

    // Test seam: inject a plain API factory (a stub). The scoped session it is
    // wrapped in creates and tears down a throwaway ephemeral session the stub
    // ignores, so the production call path is exercised without a network call.
    init(apiFactory: @escaping @Sendable (AIEndpoint) -> any OpenAICompatible) {
        self.init(sessionFactory: { config in
            ScopedAPISession(timeout: 60) { _ in apiFactory(config) }
        })
    }

    init(sessionFactory: @escaping @Sendable (AIEndpoint) -> ScopedAPISession<any OpenAICompatible>) {
        self.sessionFactory = sessionFactory
    }
}

extension LLMMetadataDataSourceImpl: MetadataDataSource {
    public func resolve(track: Track) async -> [Track] {
        guard let ai = configDataSource.load()?.config.ai else { return [] }
        let aiConfig = AIEndpoint(endpoint: ai.endpoint, model: ai.model, apiKey: ai.apiKey)

        guard let metadata = await callAPI(config: aiConfig, rawTitle: track.title, rawArtist: track.artist),
            !metadata.title.isEmpty
        else { return [] }
        return [Track(title: metadata.title, artist: metadata.artist)]
    }
}

extension LLMMetadataDataSourceImpl {
    fileprivate func callAPI(config: AIEndpoint, rawTitle: String, rawArtist: String) async -> ExtractedMetadata? {
        let request = MetadataExtractionPrompt(rawTitle: rawTitle, rawArtist: rawArtist)
            .request(model: config.model)

        let response: ChatCompletionResponse
        do {
            response = try await sessionFactory(config).withAPI { try await $0.chatCompletion(request: request) }
        } catch {
            fputs("lyra: AI extraction failed: \(error)\n", stderr)
            return nil
        }

        guard let content = response.choices.first?.message.content,
            let data = content.data(using: .utf8)
        else { return nil }

        return try? JSONDecoder().decode(ExtractedMetadata.self, from: data)
    }
}
