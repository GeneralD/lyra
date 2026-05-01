import Dependencies
import Domain
import Foundation
@preconcurrency import Papyrus

public struct LLMMetadataDataSourceImpl {
    @Dependency(\.configDataSource) private var configDataSource
    private let apiFactory: @Sendable (AIEndpoint) -> any OpenAICompatible

    public init() {
        self.init { config in
            OpenAICompatibleAPI(provider: OpenAICompatibleAPI.provider(for: config))
        }
    }

    init(apiFactory: @escaping @Sendable (AIEndpoint) -> any OpenAICompatible) {
        self.apiFactory = apiFactory
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
        let api = apiFactory(config)
        let request = MetadataExtractionPrompt(rawTitle: rawTitle, rawArtist: rawArtist)
            .request(model: config.model)

        let response: ChatCompletionResponse
        do {
            response = try await api.chatCompletion(request: request)
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
