import Dependencies
import Domain
import Testing

@testable import MetadataDataSource

@Suite("LLMNormalizer")
struct LLMNormalizerTests {
    @Test("Returns empty when AI is not configured")
    func unconfiguredReturnsEmpty() async {
        let normalizer = withDependencies {
            $0.appStyle = AppStyle(ai: nil)
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
            $0.appStyle = AppStyle(ai: AIEndpoint(
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
            $0.appStyle = AppStyle(ai: nil)
            $0.metadataCache = NoopMetadataCache()
            $0.metadataNormalizers = [LLMNormalizer(), RegexNormalizer()]
        } operation: { () -> [Track] in
            @Dependency(\.metadataNormalizers) var normalizers
            let track = Track(title: "Artist - Song Title", artist: "SomeChannel")
            // LLMNormalizer returns empty (no AI config) → RegexNormalizer produces candidates
            let llmResult = await normalizers[0].resolve(track: track)
            #expect(llmResult.isEmpty)
            let regexResult = await normalizers[1].resolve(track: track)
            #expect(!regexResult.isEmpty)
            return regexResult
        }
        #expect(!result.isEmpty)
        // RegexNormalizer parses "Artist - Song Title" → title: "Song Title", artist: "Artist"
        #expect(result.contains(where: { $0.title == "Song Title" && $0.artist == "Artist" }))
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
    func read(title: String, artist: String) async -> MusicBrainzMetadata? { nil }
    func write(queryTitle: String, queryArtist: String, metadata: MusicBrainzMetadata) async throws {}
}
