import Domain
import Foundation
@preconcurrency import Papyrus
import ScopedAPISession

public struct LyricsDataSourceImpl {
    private let apiSession: ScopedAPISession<any LRCLib>

    public init() {
        self.init(
            apiSession: ScopedAPISession(timeout: 10) {
                LRCLibAPI(provider: Provider(baseURL: LRCLibAPI.baseURL, urlSession: $0))
            }
        )
    }

    init(api: any LRCLib) {
        self.init(apiSession: ScopedAPISession(timeout: 10) { _ in api })
    }

    init(apiSession: ScopedAPISession<any LRCLib>) {
        self.apiSession = apiSession
    }
}

extension LyricsDataSourceImpl: Sendable {}

extension LyricsDataSourceImpl: LyricsDataSource {
    public func get(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? {
        do {
            let result = try await apiSession.withAPI {
                try await $0.get(trackName: title, artistName: artist, duration: duration.map(Int.init))
            }
            guard result.plainLyrics != nil || result.syncedLyrics != nil else { return nil }
            return result
        } catch {
            log(error, operation: "get")
            return nil
        }
    }

    public func search(query: String) async -> [LyricsResult]? {
        do {
            return try await apiSession.withAPI { try await $0.search(q: query) }
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
