import Dependencies
import Domain
import Testing

@testable import TitleExtraction

@Suite("LLMNormalizer")
struct LLMNormalizerTests {
    @Test("Returns empty when AI is not configured")
    func unconfiguredReturnsEmpty() async {
        let normalizer = withDependencies {
            $0.config = ResolvedConfig(ai: nil)
        } operation: {
            LLMNormalizer()
        }

        let result = await normalizer.resolve(track: Track(title: "Some Song", artist: "Some Artist"))
        #expect(result.isEmpty)
    }

    @Test("Returns cached result without API call")
    func cacheHitSkipsAPI() async {
        let expected = Track(title: "Cached Title", artist: "Cached Artist")
        let normalizer = withDependencies {
            $0.config = ResolvedConfig(ai: ResolvedAIConfig(
                endpoint: "https://example.com/v1",
                model: "test-model",
                apiKey: "test-key"
            ))
            $0.aiMetadataCache = StubAIMetadataCache(stubbedResult: expected)
        } operation: {
            LLMNormalizer()
        }

        let result = await normalizer.resolve(track: Track(title: "raw title", artist: "raw artist"))
        #expect(result == [expected])
    }
}

@Suite("MetadataNormalizer pipeline")
struct MetadataNormalizerPipelineTests {
    @Test("Falls back to regex when LLM returns empty")
    func llmFallbackToRegex() async {
        let llmNormalizer = FailingMetadataNormalizer()
        let regexNormalizer = StubMetadataNormalizer(candidates: [
            Track(title: "Regex Title", artist: "Regex Artist"),
        ])

        let normalizers: [any MetadataNormalizer] = [llmNormalizer, regexNormalizer]
        var result: [Track] = []
        for normalizer in normalizers {
            result = await normalizer.resolve(track: Track(title: "raw", artist: "raw"))
            guard result.isEmpty else { break }
        }
        #expect(result == [Track(title: "Regex Title", artist: "Regex Artist")])
    }

    @Test("Uses LLM result when available, skips regex")
    func llmSuccessSkipsRegex() async {
        let llmNormalizer = StubMetadataNormalizer(candidates: [
            Track(title: "LLM Title", artist: "LLM Artist"),
        ])
        let regexNormalizer = StubMetadataNormalizer(candidates: [
            Track(title: "Regex Title", artist: "Regex Artist"),
        ])

        let normalizers: [any MetadataNormalizer] = [llmNormalizer, regexNormalizer]
        var result: [Track] = []
        for normalizer in normalizers {
            result = await normalizer.resolve(track: Track(title: "raw", artist: "raw"))
            guard result.isEmpty else { break }
        }
        #expect(result == [Track(title: "LLM Title", artist: "LLM Artist")])
    }

    @Test("LLM unconfigured returns empty, enabling fallback")
    func unconfiguredLLMFallsThrough() async {
        let result = await withDependencies {
            $0.config = ResolvedConfig(ai: nil)
            $0.metadataCache = NoopMetadataCache()
            $0.metadataNormalizers = [LLMNormalizer(), RegexNormalizer()]
        } operation: { () -> [Track] in
            @Dependency(\.metadataNormalizers) var normalizers
            for normalizer in normalizers {
                let candidates = await normalizer.resolve(
                    track: Track(title: "Artist - Song Title", artist: "SomeChannel")
                )
                guard candidates.isEmpty else { return candidates }
            }
            return []
        }
        #expect(!result.isEmpty)
        #expect(result.first?.title == "Song Title")
        #expect(result.first?.artist == "Artist")
    }
}

// MARK: - Test helpers

private struct StubAIMetadataCache: AIMetadataCacheRepository {
    let stubbedResult: Track?

    func read(rawTitle: String, rawArtist: String) async -> Track? { stubbedResult }
    func write(rawTitle: String, rawArtist: String, candidate: Track) async throws {}
}

private struct FailingMetadataNormalizer: MetadataNormalizer {
    func resolve(track: Track) async -> [Track] { [] }
}

private struct StubMetadataNormalizer: MetadataNormalizer {
    let candidates: [Track]
    func resolve(track: Track) async -> [Track] { candidates }
}

private struct NoopMetadataCache: MetadataCacheRepository {
    func read(title: String, artist: String) async -> ResolvedMetadata? { nil }
    func write(queryTitle: String, queryArtist: String, metadata: ResolvedMetadata) async throws {}
}
