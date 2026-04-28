import Domain
import Foundation
@preconcurrency import Papyrus

@testable import LyricsDataSource

/// Manual mock of the `LRCLib` protocol for testing `LyricsDataSourceImpl`
/// without exercising URL construction or networking.
struct LRCLibStub: LRCLib, @unchecked Sendable {
    let getResult: @Sendable (_ trackName: String, _ artistName: String, _ duration: Int?) async throws -> LyricsResult
    let searchResult: @Sendable (_ q: String) async throws -> [LyricsResult]
    let healthCheckResult: @Sendable () async throws -> Response

    init(
        get: @escaping @Sendable (_ trackName: String, _ artistName: String, _ duration: Int?) async throws -> LyricsResult = { _, _, _ in .empty
        },
        search: @escaping @Sendable (_ q: String) async throws -> [LyricsResult] = { _ in [] },
        healthCheck: @escaping @Sendable () async throws -> Response = {
            TestResponse(
                request: URLRequest(url: URL(string: "https://lrclib.net/api/search?q=test")!),
                statusCode: 200,
                body: Data()
            )
        }
    ) {
        self.getResult = get
        self.searchResult = search
        self.healthCheckResult = healthCheck
    }

    func get(trackName: String, artistName: String, duration: Int?) async throws -> LyricsResult {
        try await getResult(trackName, artistName, duration)
    }

    func search(q: String) async throws -> [LyricsResult] {
        try await searchResult(q)
    }

    func healthCheck() async throws -> Response {
        try await healthCheckResult()
    }
}

struct StubError: Error, LocalizedError, Sendable {
    let message: String
    init(_ message: String = "stubbed failure") { self.message = message }
    var errorDescription: String? { message }
}
