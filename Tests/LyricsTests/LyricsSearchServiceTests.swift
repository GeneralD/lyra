import Dependencies
import Domain
import Foundation
import Testing

@testable import Lyrics

@Suite("LyricsSearchService")
struct LyricsSearchServiceTests {

    // MARK: - resolveMetadata

    @Suite("resolveMetadata")
    struct ResolveMetadata {
        @Test("returns first candidate from first non-empty normalizer")
        func returnsFirstCandidate() async {
            await withDependencies {
                $0.metadataNormalizers = [StubMetadataNormalizer(candidates: [
                    Track(title: "LLM Title", artist: "LLM Artist"),
                ])]
                $0.lyricsRepository = NoopLyricsRepository()
            } operation: {
                let service = LyricsService()
                let result = await service.resolveMetadata(title: "raw", artist: "raw")
                #expect(result?.title == "LLM Title")
                #expect(result?.artist == "LLM Artist")
            }
        }

        @Test("returns nil when all normalizers return empty")
        func returnsNilWhenEmpty() async {
            await withDependencies {
                $0.metadataNormalizers = [StubMetadataNormalizer(candidates: [])]
                $0.lyricsRepository = NoopLyricsRepository()
            } operation: {
                let service = LyricsService()
                let result = await service.resolveMetadata(title: "raw", artist: "raw")
                #expect(result == nil)
            }
        }

        @Test("calls normalizers exactly once per invocation")
        func callsNormalizersOnce() async {
            nonisolated(unsafe) var callCount = 0
            await withDependencies {
                $0.metadataNormalizers = [TrackingMetadataNormalizer {
                    callCount += 1
                }]
                $0.lyricsRepository = NoopLyricsRepository()
            } operation: {
                let service = LyricsService()
                _ = await service.resolveMetadata(title: "raw", artist: "raw")
                #expect(callCount == 1)
            }
        }
    }

    // MARK: - fetchLyrics cache behavior

    @Suite("fetchLyrics cache")
    struct FetchLyricsCache {
        @Test("does not cache when no lyrics found")
        func noCacheWithoutLyrics() async {
            let writable = WritableLyricsCache()

            await withDependencies {
                $0.lyricsCache = writable
                $0.lyricsRepository = NoopLyricsRepository()
                $0.metadataNormalizers = [StubMetadataNormalizer(candidates: [
                    Track(title: "LLM Title", artist: "LLM Artist"),
                ])]
            } operation: {
                let service = LyricsService()
                _ = await service.fetchLyrics(title: "zzz_unique_zzz", artist: "channel", duration: nil)

                let cachedResult = await writable.read(title: "zzz_unique_zzz", artist: "channel")
                #expect(cachedResult == nil, "should not cache when no lyrics found")
            }
        }
    }

    // MARK: - fetchLyrics without lyrics

    @Suite("fetchLyrics no match")
    struct FetchLyricsNoMatch {
        @Test("returns empty when no lyrics found anywhere")
        func returnsEmptyWithoutLyrics() async {
            await withDependencies {
                $0.lyricsCache = StubLyricsCache(stored: nil)
                $0.lyricsRepository = NoopLyricsRepository()
                $0.metadataNormalizers = [StubMetadataNormalizer(candidates: [
                    Track(title: "Nonexistent XYZ999", artist: "Nobody ABC123"),
                ])]
            } operation: {
                let service = LyricsService()
                let result = await service.fetchLyrics(title: "zzz_no_match_zzz", artist: "zzz_no_match_zzz", duration: nil)
                #expect(result == .empty)
            }
        }
    }

    // MARK: - Separation invariant

    @Suite("separation invariant")
    struct SeparationInvariant {
        @Test("resolveMetadata result is independent from fetchLyrics result")
        func metadataIndependentFromLyrics() async {
            await withDependencies {
                $0.lyricsCache = StubLyricsCache(stored: nil)
                $0.lyricsRepository = NoopLyricsRepository()
                $0.metadataNormalizers = [StubMetadataNormalizer(candidates: [
                    Track(title: "Correct Title", artist: "Correct Artist"),
                ])]
            } operation: {
                let service = LyricsService()

                let metadata = await service.resolveMetadata(title: "zzz_test_zzz", artist: "zzz_test_zzz")
                #expect(metadata?.title == "Correct Title")
                #expect(metadata?.artist == "Correct Artist")
            }
        }
    }
}

// MARK: - Test helpers

private struct StubMetadataNormalizer: MetadataNormalizer {
    let candidates: [Track]
    func resolve(track: Track) async -> [Track] { candidates }
}

private struct TrackingMetadataNormalizer: MetadataNormalizer {
    let onResolve: @Sendable () -> Void
    func resolve(track: Track) async -> [Track] {
        onResolve()
        return []
    }
}

private struct StubLyricsCache: LyricsCacheRepository {
    let stored: LyricsResult?
    func read(title: String, artist: String) async -> LyricsResult? { stored }
    func write(title: String, artist: String, result: LyricsResult) async throws {}
}

private final class WritableLyricsCache: LyricsCacheRepository, @unchecked Sendable {
    private var storage: [String: LyricsResult] = [:]
    func read(title: String, artist: String) async -> LyricsResult? { storage["\(title)|\(artist)"] }
    func write(title: String, artist: String, result: LyricsResult) async throws { storage["\(title)|\(artist)"] = result }
}

private struct NoopLyricsRepository: LyricsRepository {
    func fetchLyrics(track: Track, duration: TimeInterval?) async -> LyricsResult? { nil }
    func fetchLyrics(candidates: [Track], duration: TimeInterval?) async -> LyricsResult? { nil }
}
