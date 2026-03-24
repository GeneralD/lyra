import Dependencies
import Domain
import Testing

@testable import MetadataDataSource

@Suite("LLMMetadataDataSourceImpl")
struct LLMMetadataDataSourceImplTests {
    @Test("Returns empty when AI is not configured")
    func unconfiguredReturnsEmpty() async {
        let normalizer = withDependencies {
            $0.appStyle = AppStyle(ai: nil)
        } operation: {
            LLMMetadataDataSourceImpl()
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
            LLMMetadataDataSourceImpl()
        }

        let result = await normalizer.resolve(track: Track(title: "raw title", artist: "raw artist"))
        #expect(result == [expected])
    }
}

@Suite("MetadataDataSource pipeline")
struct MetadataDataSourcePipelineTests {
    @Test("Falls back to regex when LLM returns empty")
    func llmFallbackToRegex() async {
        let llmNormalizer = FailingMetadataDataSource()
        let regexNormalizer = StubMetadataDataSource(candidates: [
            Track(title: "Regex Title", artist: "Regex Artist"),
        ])

        let normalizers: [any MetadataDataSource] = [llmNormalizer, regexNormalizer]
        var result: [Track] = []
        for normalizer in normalizers {
            result = await normalizer.resolve(track: Track(title: "raw", artist: "raw"))
            guard result.isEmpty else { break }
        }
        #expect(result == [Track(title: "Regex Title", artist: "Regex Artist")])
    }

    @Test("Uses LLM result when available, skips regex")
    func llmSuccessSkipsRegex() async {
        let llmNormalizer = StubMetadataDataSource(candidates: [
            Track(title: "LLM Title", artist: "LLM Artist"),
        ])
        let regexNormalizer = StubMetadataDataSource(candidates: [
            Track(title: "Regex Title", artist: "Regex Artist"),
        ])

        let normalizers: [any MetadataDataSource] = [llmNormalizer, regexNormalizer]
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
            $0.metadataDataSources = [LLMMetadataDataSourceImpl(), MusicBrainzMetadataDataSourceImpl()]
        } operation: { () -> [Track] in
            @Dependency(\.metadataDataSources) var normalizers
            let track = Track(title: "Artist - Song Title", artist: "SomeChannel")
            // LLMMetadataDataSourceImpl returns empty (no AI config) → MusicBrainzMetadataDataSourceImpl produces candidates
            let llmResult = await normalizers[0].resolve(track: track)
            #expect(llmResult.isEmpty)
            let regexResult = await normalizers[1].resolve(track: track)
            #expect(!regexResult.isEmpty)
            return regexResult
        }
        #expect(!result.isEmpty)
        // MusicBrainzMetadataDataSourceImpl parses "Artist - Song Title" → title: "Song Title", artist: "Artist"
        #expect(result.contains(where: { $0.title == "Song Title" && $0.artist == "Artist" }))
    }
}

// MARK: - Test helpers

private struct StubAIMetadataCache: AIMetadataDataStore {
    let stubbedResult: Track?

    func read(rawTitle: String, rawArtist: String) async -> Track? { stubbedResult }
    func write(rawTitle: String, rawArtist: String, candidate: Track) async throws {}
}

private struct FailingMetadataDataSource: MetadataDataSource {
    func resolve(track: Track) async -> [Track] { [] }
}

private struct StubMetadataDataSource: MetadataDataSource {
    let candidates: [Track]
    func resolve(track: Track) async -> [Track] { candidates }
}

private struct NoopMetadataCache: MetadataDataStore {
    func read(title: String, artist: String) async -> MusicBrainzMetadata? { nil }
    func write(queryTitle: String, queryArtist: String, metadata: MusicBrainzMetadata) async throws {}
}
