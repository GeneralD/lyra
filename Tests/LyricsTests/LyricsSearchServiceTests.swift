import Dependencies
import Domain
import Foundation
import Testing

@testable import Lyrics
@testable import LyricsSearch
@testable import TitleExtraction

@Suite("LyricsSearchService.fetch")
struct LyricsSearchServiceTests {

    // MARK: - Cache behavior

    @Suite("cache behavior")
    struct CacheBehavior {
        @Test("lyrics cache hit returns result with correct trackName/artistName")
        @MainActor
        func cacheHitPreservesDisplayMetadata() async {
            let cached = LyricsResult(
                trackName: "Resolved Title", artistName: "Resolved Artist",
                syncedLyrics: "[00:01.00] Hello"
            )
            nonisolated(unsafe) var extractorCalled = false

            await withDependencies {
                $0.lyricsCache = StubLyricsCache(stored: cached)
                $0.titleExtractors = [TrackingTitleExtractor(onExtract: { extractorCalled = true })]
                $0.metadataCache = NoopMetadataCache()
            } operation: {
                let service = LyricsSearchService()
                let result = await service.fetch(title: "raw", artist: "raw", duration: nil) { _ in }
                #expect(result?.trackName == "Resolved Title")
                #expect(result?.artistName == "Resolved Artist")
                #expect(!extractorCalled, "titleExtractors should not be called on cache hit")
            }
        }

        @Test("lyrics cache hit does NOT call onMetadataResolved")
        @MainActor
        func cacheHitSkipsCallback() async {
            let cached = LyricsResult(trackName: "T", artistName: "A", syncedLyrics: "[00:01.00] Hi")
            nonisolated(unsafe) var callbackCalled = false

            await withDependencies {
                $0.lyricsCache = StubLyricsCache(stored: cached)
                $0.titleExtractors = []
                $0.metadataCache = NoopMetadataCache()
            } operation: {
                let service = LyricsSearchService()
                _ = await service.fetch(title: "raw", artist: "raw", duration: nil) { _ in
                    callbackCalled = true
                }
                #expect(!callbackCalled, "onMetadataResolved should not be called on cache hit")
            }
        }
    }

    // MARK: - Display metadata (withDisplay)

    @Suite("display metadata")
    struct DisplayMetadata {
        @Test("cached result preserves withDisplay values on subsequent cache hits")
        @MainActor
        func cachedWithDisplayPersists() async {
            let writable = WritableLyricsCache()

            await withDependencies {
                $0.lyricsCache = writable
                $0.titleExtractors = [StubTitleExtractor(candidates: [
                    SearchCandidate(title: "AI Title", artist: "AI Artist"),
                ])]
                $0.metadataCache = NoopMetadataCache()
            } operation: {
                let service = LyricsSearchService()

                // First call — cache miss, should resolve and cache with withDisplay
                // Note: fetchLyrics will return nil (no LRCLIB), but result should still have metadata
                let first = await service.fetch(title: "raw", artist: "channel", duration: nil) { _ in }
                #expect(first?.trackName == "AI Title")
                #expect(first?.artistName == "AI Artist")

                // Verify what was written to cache
                let cachedResult = await writable.read(title: "raw", artist: "channel")
                #expect(cachedResult?.trackName == "AI Title")
                #expect(cachedResult?.artistName == "AI Artist")
            }
        }
    }

    // MARK: - Metadata resolution + callback

    @Suite("metadata callback")
    struct MetadataCallback {
        @Test("onMetadataResolved is called with first candidate before lyrics search")
        @MainActor
        func callbackCalledWithCandidate() async {
            nonisolated(unsafe) var resolvedCandidate: SearchCandidate?

            await withDependencies {
                $0.lyricsCache = StubLyricsCache(stored: nil)
                $0.titleExtractors = [StubTitleExtractor(candidates: [
                    SearchCandidate(title: "Extracted", artist: "Artist"),
                ])]
                $0.metadataCache = NoopMetadataCache()
            } operation: {
                let service = LyricsSearchService()
                _ = await service.fetch(title: "raw", artist: "raw", duration: nil) { candidate in
                    resolvedCandidate = candidate
                }
                #expect(resolvedCandidate?.title == "Extracted")
                #expect(resolvedCandidate?.artist == "Artist")
            }
        }

        @Test("onMetadataResolved is NOT called when extractors return empty")
        @MainActor
        func callbackNotCalledWhenEmpty() async {
            nonisolated(unsafe) var callbackCalled = false

            await withDependencies {
                $0.lyricsCache = StubLyricsCache(stored: nil)
                $0.titleExtractors = [StubTitleExtractor(candidates: [])]
                $0.metadataCache = NoopMetadataCache()
            } operation: {
                let service = LyricsSearchService()
                _ = await service.fetch(title: "raw", artist: "raw", duration: nil) { _ in
                    callbackCalled = true
                }
                #expect(!callbackCalled)
            }
        }
    }

    // MARK: - Lyrics not found

    @Suite("lyrics not found")
    struct LyricsNotFound {
        @Test("returns result with trackName/artistName even when no lyrics found")
        @MainActor
        func metadataReturnedWithoutLyrics() async {
            await withDependencies {
                $0.lyricsCache = StubLyricsCache(stored: nil)
                $0.titleExtractors = [StubTitleExtractor(candidates: [
                    SearchCandidate(title: "Nonexistent Song XYZ999", artist: "Nobody Artist ABC123"),
                ])]
                $0.metadataCache = NoopMetadataCache()
            } operation: {
                let service = LyricsSearchService()
                let result = await service.fetch(title: "zzz_no_match_zzz", artist: "zzz_no_match_zzz", duration: nil) { _ in }
                #expect(result?.trackName == "Nonexistent Song XYZ999")
                #expect(result?.artistName == "Nobody Artist ABC123")
                #expect(result?.plainLyrics == nil)
                #expect(result?.syncedLyrics == nil)
            }
        }
    }

    // MARK: - Invariants

    @Suite("invariants")
    struct Invariants {
        @Test("onMetadataResolved candidate matches result's trackName/artistName")
        @MainActor
        func callbackMatchesResult() async {
            nonisolated(unsafe) var resolvedCandidate: SearchCandidate?

            await withDependencies {
                $0.lyricsCache = StubLyricsCache(stored: nil)
                $0.titleExtractors = [StubTitleExtractor(candidates: [
                    SearchCandidate(title: "Consistent", artist: "Value"),
                ])]
                $0.metadataCache = NoopMetadataCache()
            } operation: {
                let service = LyricsSearchService()
                let result = await service.fetch(title: "raw", artist: "raw", duration: nil) { candidate in
                    resolvedCandidate = candidate
                }
                #expect(resolvedCandidate?.title == result?.trackName)
                #expect(resolvedCandidate?.artist == result?.artistName)
            }
        }
    }

    // MARK: - Convenience overload (no callback)

    @Suite("convenience API")
    struct ConvenienceAPI {
        @Test("fetch works without onMetadataResolved callback")
        @MainActor
        func fetchWithoutCallback() async {
            let cached = LyricsResult(
                trackName: "Title", artistName: "Artist",
                syncedLyrics: "[00:01.00] Lyrics"
            )

            await withDependencies {
                $0.lyricsCache = StubLyricsCache(stored: cached)
                $0.titleExtractors = []
                $0.metadataCache = NoopMetadataCache()
            } operation: {
                let service = LyricsSearchService()
                let result = await service.fetch(title: "raw", artist: "raw", duration: nil)
                #expect(result?.trackName == "Title")
            }
        }
    }
}

// MARK: - LyricsService convenience

@Suite("LyricsService")
struct LyricsServiceConvenienceTests {
    @Test("fetch works without onMetadataResolved callback")
    @MainActor
    func fetchWithoutCallback() async {
        let expected = LyricsResult(id: 5, syncedLyrics: "[00:01.00] Test")

        await withDependencies {
            $0.lyricsRepository = SimpleRepository(result: expected)
        } operation: {
            let service = LyricsService()
            let result = await service.fetch(title: "T", artist: "A", duration: nil)
            #expect(result.id == 5)
        }
    }
}

private struct SimpleRepository: LyricsRepository {
    let result: LyricsResult?
    func fetch(title: String, artist: String, duration: TimeInterval?, onMetadataResolved: @MainActor @Sendable (SearchCandidate) -> Void) async -> LyricsResult? { result }
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
    let candidates: [SearchCandidate]
    func extract(rawTitle: String, rawArtist: String) async -> [SearchCandidate] { candidates }
}

private final class TrackingTitleExtractor: TitleExtractor, @unchecked Sendable {
    let onExtract: () -> Void
    init(onExtract: @escaping () -> Void) { self.onExtract = onExtract }
    func extract(rawTitle: String, rawArtist: String) async -> [SearchCandidate] {
        onExtract()
        return []
    }
}

private struct NoopMetadataCache: MetadataCacheRepository {
    func read(title: String, artist: String) async -> ResolvedMetadata? { nil }
    func write(queryTitle: String, queryArtist: String, metadata: ResolvedMetadata) async throws {}
}
