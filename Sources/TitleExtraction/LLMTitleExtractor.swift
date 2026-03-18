import Dependencies
import Domain
import Foundation

public struct LLMTitleExtractor {
    @Dependency(\.config) private var config
    @Dependency(\.aiMetadataCache) private var cache

    public init() {}
}

extension LLMTitleExtractor: TitleExtractor {
    public func extract(rawTitle: String, rawArtist: String) async -> [ResolvedTrack] {
        guard let aiConfig = config.ai else { return [] }

        if let cached = await cache.read(rawTitle: rawTitle, rawArtist: rawArtist) {
            return [cached]
        }

        guard let metadata = await callAPI(config: aiConfig, rawTitle: rawTitle, rawArtist: rawArtist),
              !metadata.title.isEmpty
        else { return [] }
        let candidate = ResolvedTrack(title: metadata.title, artist: metadata.artist)
        try? await cache.write(rawTitle: rawTitle, rawArtist: rawArtist, candidate: candidate)
        return [candidate]
    }
}

private extension LLMTitleExtractor {
    func callAPI(config: ResolvedAIConfig, rawTitle: String, rawArtist: String) async -> ExtractedMetadata? {
        let api = OpenAICompatibleAPI(config: config)
        guard let request = try? api.chatCompletion(rawTitle: rawTitle, rawArtist: rawArtist) else { return nil }

        let data: Data
        let urlResponse: URLResponse
        do {
            (data, urlResponse) = try await URLSession.shared.data(for: request)
        } catch {
            fputs("lyra: AI extraction failed: \(error)\n", stderr)
            return nil
        }

        guard let httpResponse = urlResponse as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode)
        else {
            let code = (urlResponse as? HTTPURLResponse)?.statusCode ?? -1
            fputs("lyra: AI extraction failed with HTTP \(code)\n", stderr)
            return nil
        }

        guard let response = try? JSONDecoder().decode(ChatCompletionResponse.self, from: data),
              let content = response.choices.first?.message.content,
              let contentData = content.data(using: .utf8)
        else { return nil }

        return try? JSONDecoder().decode(ExtractedMetadata.self, from: contentData)
    }
}

// MARK: - DependencyKey

extension TitleExtractorKey: DependencyKey {
    public static let liveValue: [any TitleExtractor] = [
        LLMTitleExtractor(),
        RegexTitleExtractor(),
    ]
}
