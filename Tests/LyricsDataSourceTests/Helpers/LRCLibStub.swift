import Domain
import Foundation

@testable import LyricsDataSource

/// Manual mock of the `LRCLib` protocol for testing `LyricsDataSourceImpl`
/// without exercising URL construction or networking.
struct LRCLibStub: LRCLib, @unchecked Sendable {
    let getResult: @Sendable (_ trackName: String, _ artistName: String, _ duration: Int?) async throws -> LyricsResult
    let searchResult: @Sendable (_ q: String) async throws -> [LyricsResult]

    init(
        get: @escaping @Sendable (_ trackName: String, _ artistName: String, _ duration: Int?) async throws -> LyricsResult = { _, _, _ in .empty
        },
        search: @escaping @Sendable (_ q: String) async throws -> [LyricsResult] = { _ in [] }
    ) {
        self.getResult = get
        self.searchResult = search
    }

    func get(trackName: String, artistName: String, duration: Int?) async throws -> LyricsResult {
        try await getResult(trackName, artistName, duration)
    }

    func search(q: String) async throws -> [LyricsResult] {
        try await searchResult(q)
    }
}

struct StubError: Error, LocalizedError, Sendable {
    let message: String
    init(_ message: String = "stubbed failure") { self.message = message }
    var errorDescription: String? { message }
}
