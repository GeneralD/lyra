import Dependencies
import Foundation
import Testing

@testable import Domain
@testable import LyricsUseCase
@testable import MetadataUseCase

@Suite("LyricsService")
struct LyricsServiceTests {
    @Test("fetchLyrics delegates to repository with candidates")
    func fetchLyrics() async {
        let expected = LyricsResult(id: 2, syncedLyrics: "[00:01.00] World")
        await withDependencies {
            $0.lyricsRepository = MockLyricsRepository(lyrics: expected)
        } operation: {
            let service = LyricsUseCaseImpl()
            let result = await service.fetchLyrics(
                candidates: [Track(title: "Test", artist: "Artist")]
            )
            #expect(result.id == 2)
        }
    }

    @Test("fetchLyrics returns empty when repository returns nil")
    func fetchLyricsReturnsEmpty() async {
        await withDependencies {
            $0.lyricsRepository = MockLyricsRepository(lyrics: nil)
        } operation: {
            let service = LyricsUseCaseImpl()
            let result = await service.fetchLyrics(
                track: Track(title: "Unknown", artist: "Nobody")
            )
            #expect(result == .empty)
        }
    }
}

@Suite("MetadataService")
struct MetadataServiceTests {
    @Test("resolve delegates to metadataRepository")
    func resolveMetadata() async {
        await withDependencies {
            $0.metadataRepository = MockMetadataRepository(candidates: [
                Track(title: "Resolved", artist: "Artist")
            ])
        } operation: {
            let service = MetadataUseCaseImpl()
            let result = await service.resolve(track: Track(title: "raw", artist: "raw"))
            #expect(result?.title == "Resolved")
            #expect(result?.artist == "Artist")
        }
    }

    @Test("resolve returns nil when repository returns empty")
    func resolveReturnsNil() async {
        await withDependencies {
            $0.metadataRepository = MockMetadataRepository(candidates: [])
        } operation: {
            let service = MetadataUseCaseImpl()
            let result = await service.resolve(track: Track(title: "raw", artist: "raw"))
            #expect(result == nil)
        }
    }
}

// MARK: - Mocks

private struct MockLyricsRepository: LyricsRepository {
    let lyrics: LyricsResult?
    func fetchLyrics(track: Track) async -> LyricsResult? { lyrics }
    func fetchLyrics(candidates: [Track]) async -> LyricsResult? { lyrics }
}

private struct MockMetadataRepository: MetadataRepository {
    let candidates: [Track]
    func resolve(track: Track) async -> [Track] { candidates }
}
