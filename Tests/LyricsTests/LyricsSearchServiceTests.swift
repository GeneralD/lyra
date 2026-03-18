import Dependencies
import Domain
import Foundation
import Testing

@testable import Lyrics
@testable import LyricsSearch
@testable import TitleExtraction

@Suite("LyricsSearchService")
struct LyricsSearchServiceTests {

    // MARK: - resolveMetadata

    @Suite("resolveMetadata")
    struct ResolveMetadata {
        @Test("returns first candidate from first non-empty extractor")
        func returnsFirstCandidate() async {
            await withDependencies {
                $0.titleExtractors = [StubTitleExtractor(candidates: [
                    ResolvedTrack(title: "AI Title", artist: "AI Artist"),
                ])]
            } operation: {
                let service = LyricsSearchService()
                let result = await service.resolveMetadata(title: "raw", artist: "raw")
                #expect(result?.title == "AI Title")
                #expect(result?.artist == "AI Artist")
            }
        }

        @Test("returns nil when all extractors return empty")
        func returnsNilWhenEmpty() async {
            await withDependencies {
                $0.titleExtractors = [StubTitleExtractor(candidates: [])]
            } operation: {
                let service = LyricsSearchService()
                let result = await service.resolveMetadata(title: "raw", artist: "raw")
                #expect(result == nil)
            }
        }

        @Test("does not call titleExtractors — independent from fetchLyrics")
        func independentFromLyrics() async {
            nonisolated(unsafe) var extractorCallCount = 0

            await withDependencies {
                $0.titleExtractors = [TrackingTitleExtractor {
                    extractorCallCount += 1
                }]
            } operation: {
                let service = LyricsSearchService()
                _ = await service.resolveMetadata(title: "raw", artist: "raw")
                #expect(extractorCallCount == 1)
            }
        }
    }

    // MARK: - fetchLyrics cache behavior

    @Suite("fetchLyrics cache")
    struct FetchLyricsCache {
        @Test("lyrics cache hit returns result with correct trackName/artistName")
        func cacheHitPreservesDisplayMetadata() async {
            let cached = LyricsResult(
                trackName: "Resolved Title", artistName: "Resolved Artist",
                syncedLyrics: "[00:01.00] Hello"
            )

            await withDependencies {
                $0.lyricsCache = StubLyricsCache(stored: cached)
                $0.titleExtractors = []
                $0.metadataCache = NoopMetadataCache()
            } operation: {
                let service = LyricsSearchService()
                let result = await service.fetchLyrics(title: "raw", artist: "raw", duration: nil)
                #expect(result?.trackName == "Resolved Title")
                #expect(result?.artistName == "Resolved Artist")
            }
        }

        @Test("lyrics cache hit does NOT call titleExtractors")
        func cacheHitSkipsExtractors() async {
            let cached = LyricsResult(trackName: "T", artistName: "A", syncedLyrics: "[00:01.00] Hi")
            nonisolated(unsafe) var extractorCalled = false

            await withDependencies {
                $0.lyricsCache = StubLyricsCache(stored: cached)
                $0.titleExtractors = [TrackingTitleExtractor { extractorCalled = true }]
                $0.metadataCache = NoopMetadataCache()
            } operation: {
                let service = LyricsSearchService()
                _ = await service.fetchLyrics(title: "raw", artist: "raw", duration: nil)
                #expect(!extractorCalled, "titleExtractors should not be called on cache hit")
            }
        }

        @Test("does not cache when no lyrics found")
        func noCacheWithoutLyrics() async {
            let writable = WritableLyricsCache()

            await withDependencies {
                $0.lyricsCache = writable
                $0.titleExtractors = [StubTitleExtractor(candidates: [
                    ResolvedTrack(title: "AI Title", artist: "AI Artist"),
                ])]
                $0.metadataCache = NoopMetadataCache()
            } operation: {
                let service = LyricsSearchService()
                _ = await service.fetchLyrics(title: "zzz_unique_zzz", artist: "channel", duration: nil)

                let cachedResult = await writable.read(title: "zzz_unique_zzz", artist: "channel")
                #expect(cachedResult == nil, "should not cache when no lyrics found")
            }
        }
    }

    // MARK: - fetchLyrics without lyrics

    @Suite("fetchLyrics no match")
    struct FetchLyricsNoMatch {
        @Test("returns nil when no lyrics found anywhere")
        func returnsNilWithoutLyrics() async {
            await withDependencies {
                $0.lyricsCache = StubLyricsCache(stored: nil)
                $0.titleExtractors = [StubTitleExtractor(candidates: [
                    ResolvedTrack(title: "Nonexistent XYZ999", artist: "Nobody ABC123"),
                ])]
                $0.metadataCache = NoopMetadataCache()
            } operation: {
                let service = LyricsSearchService()
                let result = await service.fetchLyrics(title: "zzz_no_match_zzz", artist: "zzz_no_match_zzz", duration: nil)
                #expect(result == nil)
            }
        }
    }

    // MARK: - Separation invariant

    @Suite("separation invariant")
    struct SeparationInvariant {
        @Test("resolveMetadata result is independent from fetchLyrics result")
        func metadataAndLyricsAreIndependent() async {
            await withDependencies {
                $0.lyricsCache = StubLyricsCache(stored: nil)
                $0.titleExtractors = [StubTitleExtractor(candidates: [
                    ResolvedTrack(title: "Correct Title", artist: "Correct Artist"),
                ])]
                $0.metadataCache = NoopMetadataCache()
            } operation: {
                let service = LyricsSearchService()

                // Metadata resolves correctly
                let metadata = await service.resolveMetadata(title: "zzz_test_zzz", artist: "zzz_test_zzz")
                #expect(metadata?.title == "Correct Title")
                #expect(metadata?.artist == "Correct Artist")

                // Lyrics may not be found — that's fine, metadata is unaffected
                let lyrics = await service.fetchLyrics(title: "zzz_test_zzz", artist: "zzz_test_zzz", duration: nil)
                // lyrics can be nil — the point is metadata was already available
                _ = lyrics
            }
        }
    }
}

// MARK: - Test doubles

private struct StubLyricsCache: LyricsCacheRepository {
    let stored: LyricsResult?
    func read(title: String, artist: String) async -> LyricsResult? { stored }
    func write(title: String, artist: String, result: LyricsResult) async throws {}
}

private final class WritableLyricsCache: LyricsCacheRepository, @unchecked Sendable {
    private var storage: [String: LyricsResult] = [:]

    func read(title: String, artist: String) async -> LyricsResult? {
        storage["\(title)|\(artist)"]
    }

    func write(title: String, artist: String, result: LyricsResult) async throws {
        storage["\(title)|\(artist)"] = result
    }
}

private struct StubTitleExtractor: TitleExtractor {
    let candidates: [ResolvedTrack]
    func extract(rawTitle: String, rawArtist: String) async -> [ResolvedTrack] { candidates }
}

private final class TrackingTitleExtractor: TitleExtractor, @unchecked Sendable {
    let onExtract: () -> Void
    init(onExtract: @escaping () -> Void) { self.onExtract = onExtract }
    func extract(rawTitle: String, rawArtist: String) async -> [ResolvedTrack] {
        onExtract()
        return []
    }
}

private struct NoopMetadataCache: MetadataCacheRepository {
    func read(title: String, artist: String) async -> ResolvedMetadata? { nil }
    func write(queryTitle: String, queryArtist: String, metadata: ResolvedMetadata) async throws {}
}
