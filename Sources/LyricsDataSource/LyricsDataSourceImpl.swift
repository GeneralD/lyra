import Dependencies
import Domain
import Foundation
@preconcurrency import Papyrus
import ScopedAPISession

public struct LyricsDataSourceImpl {
    @Dependency(\.errorLog) private var errorLog
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
            log(error, operation: "search(q)")
            return nil
        }
    }

    public func search(trackName: String) async -> [LyricsResult]? {
        do {
            return try await apiSession.withAPI { try await $0.search(trackName: trackName) }
        } catch {
            log(error, operation: "search(track_name)")
            return nil
        }
    }
}

extension LyricsDataSourceImpl {
    // 404 is LRCLIB's regular "no lyrics for this track" answer; only transport
    // and server failures are worth surfacing so "no lyrics" and "fetch broken"
    // stay distinguishable in the daemon log (#318).
    //
    // The guard stays here rather than moving into the sink: that a 404 means "no
    // lyrics" is LRCLIB's own contract, not something a general error log could know.
    // What #345 changed is that it is now guarding a *dependency* — so the rule can
    // finally be pinned by a test instead of resting on this comment.
    private func log(_ error: some Error, operation: String) {
        if let papyrusError = error as? PapyrusError, papyrusError.response?.statusCode == 404 { return }
        errorLog.record(.lrclib, "\(operation) failed: \(error)")
    }
}
