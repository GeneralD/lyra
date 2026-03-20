import Dependencies
import Foundation
import Testing
@testable import Domain
@testable import Lyrics

@Suite("LyricsService")
struct LyricsServiceTests {
    @Test("resolveMetadata delegates to repository")
    func resolveMetadata() async {
        await withDependencies {
            $0.lyricsRepository = MockLyricsRepository(
                metadata: Track(title: "Resolved", artist: "Artist"),
                lyrics: nil
            )
        } operation: {
            let service = LyricsService()
            let result = await service.resolveMetadata(title: "raw", artist: "raw")
            #expect(result?.title == "Resolved")
            #expect(result?.artist == "Artist")
        }
    }

    @Test("fetchLyrics delegates to repository")
    func fetchLyrics() async {
        let expected = LyricsResult(id: 2, syncedLyrics: "[00:01.00] World")
        await withDependencies {
            $0.lyricsRepository = MockLyricsRepository(metadata: nil, lyrics: expected)
        } operation: {
            let service = LyricsService()
            let result = await service.fetchLyrics(title: "Test", artist: "Artist", duration: nil)
            #expect(result.id == 2)
        }
    }

    @Test("fetchLyrics returns empty when repository returns nil")
    func fetchLyricsReturnsEmpty() async {
        await withDependencies {
            $0.lyricsRepository = MockLyricsRepository(metadata: nil, lyrics: nil)
        } operation: {
            let service = LyricsService()
            let result = await service.fetchLyrics(title: "Unknown", artist: "Nobody", duration: nil)
            #expect(result == .empty)
        }
    }
}

// MARK: - Mocks

private struct MockLyricsRepository: LyricsRepository {
    let metadata: Track?
    let lyrics: LyricsResult?

    func resolveMetadata(title: String, artist: String) async -> Track? { metadata }
    func fetchLyrics(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? { lyrics }
}
