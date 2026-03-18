import Dependencies
import Domain
import Testing

@testable import TitleExtraction

@Suite("LLMTitleExtractor")
struct LLMTitleExtractorTests {
    @Test("Returns empty when AI is not configured")
    func unconfiguredReturnsEmpty() async {
        let extractor = withDependencies {
            $0.config = ResolvedConfig(ai: nil)
        } operation: {
            LLMTitleExtractor()
        }

        let result = await extractor.extract(rawTitle: "Some Song", rawArtist: "Some Artist")
        #expect(result.isEmpty)
    }

    @Test("Returns cached result without API call")
    func cacheHitSkipsAPI() async {
        let expected = ResolvedTrack(title: "Cached Title", artist: "Cached Artist")
        let extractor = withDependencies {
            $0.config = ResolvedConfig(ai: ResolvedAIConfig(
                endpoint: "https://example.com/v1",
                model: "test-model",
                apiKey: "test-key"
            ))
            $0.aiMetadataCache = StubAIMetadataCache(stubbedResult: expected)
        } operation: {
            LLMTitleExtractor()
        }

        let result = await extractor.extract(rawTitle: "raw title", rawArtist: "raw artist")
        #expect(result == [expected])
    }
}

@Suite("TitleExtractor pipeline")
struct TitleExtractorPipelineTests {
    @Test("Falls back to regex when AI returns empty")
    func aiFallbackToRegex() async {
        let aiExtractor = FailingTitleExtractor()
        let regexExtractor = StubTitleExtractor(candidates: [
            ResolvedTrack(title: "Regex Title", artist: "Regex Artist"),
        ])

        let extractors: [any TitleExtractor] = [aiExtractor, regexExtractor]
        var result: [ResolvedTrack] = []
        for extractor in extractors {
            result = await extractor.extract(rawTitle: "raw", rawArtist: "raw")
            guard result.isEmpty else { break }
        }
        #expect(result == [ResolvedTrack(title: "Regex Title", artist: "Regex Artist")])
    }

    @Test("Uses AI result when available, skips regex")
    func aiSuccessSkipsRegex() async {
        let aiExtractor = StubTitleExtractor(candidates: [
            ResolvedTrack(title: "AI Title", artist: "AI Artist"),
        ])
        let regexExtractor = StubTitleExtractor(candidates: [
            ResolvedTrack(title: "Regex Title", artist: "Regex Artist"),
        ])

        let extractors: [any TitleExtractor] = [aiExtractor, regexExtractor]
        var result: [ResolvedTrack] = []
        for extractor in extractors {
            result = await extractor.extract(rawTitle: "raw", rawArtist: "raw")
            guard result.isEmpty else { break }
        }
        #expect(result == [ResolvedTrack(title: "AI Title", artist: "AI Artist")])
    }

    @Test("LLM unconfigured returns empty, enabling fallback")
    func unconfiguredLLMFallsThrough() async {
        let result = await withDependencies {
            $0.config = ResolvedConfig(ai: nil)
            $0.titleExtractors = [LLMTitleExtractor(), RegexTitleExtractor()]
        } operation: { () -> [ResolvedTrack] in
            @Dependency(\.titleExtractors) var extractors
            for extractor in extractors {
                let candidates = await extractor.extract(
                    rawTitle: "Artist - Song Title",
                    rawArtist: "SomeChannel"
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
    let stubbedResult: ResolvedTrack?

    func read(rawTitle: String, rawArtist: String) async -> ResolvedTrack? { stubbedResult }
    func write(rawTitle: String, rawArtist: String, candidate: ResolvedTrack) async throws {}
}

private struct FailingTitleExtractor: TitleExtractor {
    func extract(rawTitle: String, rawArtist: String) async -> [ResolvedTrack] { [] }
}

private struct StubTitleExtractor: TitleExtractor {
    let candidates: [ResolvedTrack]
    func extract(rawTitle: String, rawArtist: String) async -> [ResolvedTrack] { candidates }
}
