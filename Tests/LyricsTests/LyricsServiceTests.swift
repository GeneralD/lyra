import Dependencies
import Foundation
import Testing
@testable import Domain
@testable import Lyrics

@Suite("LyricsService")
struct LyricsServiceTests {
    @Test("resolveMetadata delegates to metadataRepository")
    func resolveMetadata() async {
        await withDependencies {
            $0.lyricsRepository = MockLyricsRepository(lyrics: nil)
            $0.metadataRepository = MockMetadataRepository(candidates: [
                Track(title: "Resolved", artist: "Artist"),
            ])
        } operation: {
            let service = LyricsService()
            let result = await service.resolveMetadata(title: "raw", artist: "raw")
            #expect(result?.title == "Resolved")
            #expect(result?.artist == "Artist")
        }
    }

    @Test("fetchLyrics uses metadataRepository then lyricsRepository")
    func fetchLyrics() async {
        let expected = LyricsResult(id: 2, syncedLyrics: "[00:01.00] World")
        await withDependencies {
            $0.lyricsRepository = MockLyricsRepository(lyrics: expected)
            $0.metadataRepository = MockMetadataRepository(candidates: [
                Track(title: "Test", artist: "Artist"),
            ])
        } operation: {
            let service = LyricsService()
            let result = await service.fetchLyrics(title: "Test", artist: "Artist", duration: nil)
            #expect(result.id == 2)
        }
    }

    @Test("fetchLyrics returns empty when both return nil/empty")
    func fetchLyricsReturnsEmpty() async {
        await withDependencies {
            $0.lyricsRepository = MockLyricsRepository(lyrics: nil)
            $0.metadataRepository = MockMetadataRepository(candidates: [])
        } operation: {
            let service = LyricsService()
            let result = await service.fetchLyrics(title: "Unknown", artist: "Nobody", duration: nil)
            #expect(result == .empty)
        }
    }
}

// MARK: - Mocks

private struct MockLyricsRepository: LyricsRepository {
    let lyrics: LyricsResult?

    func fetchLyrics(track: Track, duration: TimeInterval?) async -> LyricsResult? { lyrics }
    func fetchLyrics(candidates: [Track], duration: TimeInterval?) async -> LyricsResult? { lyrics }
}

private struct MockMetadataRepository: MetadataRepository {
    let candidates: [Track]
    func resolve(track: Track) async -> [Track] { candidates }
}
