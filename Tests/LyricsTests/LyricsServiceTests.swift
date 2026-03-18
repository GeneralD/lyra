import Dependencies
import Foundation
import Testing
@testable import Domain
@testable import Lyrics

@Suite("LyricsService")
struct LyricsServiceTests {
    @Test("delegates to repository")
    func delegatesToRepository() async {
        let expected = LyricsResult(id: 2, syncedLyrics: "[00:01.00] World")

        await withDependencies {
            $0.lyricsRepository = MockLyricsRepository(result: expected)
        } operation: {
            let service = LyricsService()
            let result = await service.fetch(title: "Test", artist: "Artist", duration: nil)
            #expect(result.id == 2)
        }
    }

    @Test("returns empty when repository returns nil")
    func returnsEmptyOnNil() async {
        await withDependencies {
            $0.lyricsRepository = MockLyricsRepository(result: nil)
        } operation: {
            let service = LyricsService()
            let result = await service.fetch(title: "Unknown", artist: "Nobody", duration: nil)
            #expect(result == .empty)
        }
    }
}

// MARK: - Mocks

private struct MockLyricsRepository: LyricsRepository {
    let result: LyricsResult?

    func fetch(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? { result }
}
