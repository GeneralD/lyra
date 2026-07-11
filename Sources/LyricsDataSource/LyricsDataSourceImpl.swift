import Domain
import Foundation
@preconcurrency import Papyrus

public struct LyricsDataSourceImpl {
    private let apiFactory: () -> any LRCLib

    public init() {
        self.init { EphemeralSessionLRCLib() }
    }

    init(api: any LRCLib) {
        self.init { api }
    }

    init(apiFactory: @escaping () -> any LRCLib) {
        self.apiFactory = apiFactory
    }
}

// Safe: `apiFactory` is set at init and never mutated; it only constructs a fresh,
// call-local API client (or returns the injected test stub).
extension LyricsDataSourceImpl: @unchecked Sendable {}

extension LyricsDataSourceImpl: LyricsDataSource {
    public func get(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? {
        do {
            let result = try await apiFactory().get(trackName: title, artistName: artist, duration: duration.map(Int.init))
            guard result.plainLyrics != nil || result.syncedLyrics != nil else { return nil }
            return result
        } catch {
            log(error, operation: "get")
            return nil
        }
    }

    public func search(query: String) async -> [LyricsResult]? {
        do {
            return try await apiFactory().search(q: query)
        } catch {
            log(error, operation: "search")
            return nil
        }
    }
}

extension LyricsDataSourceImpl {
    // 404 is LRCLIB's regular "no lyrics for this track" answer; only transport
    // and server failures are worth surfacing so "no lyrics" and "fetch broken"
    // stay distinguishable in the daemon log (#318).
    private func log(_ error: some Error, operation: String) {
        if let papyrusError = error as? PapyrusError, papyrusError.response?.statusCode == 404 { return }
        fputs("lyra: LRCLIB \(operation) failed: \(error)\n", stderr)
    }
}
