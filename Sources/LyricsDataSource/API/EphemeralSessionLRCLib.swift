import Domain
import Foundation
@preconcurrency import Papyrus

/// A call-scoped LRCLib client owning a fresh ephemeral `URLSession` (#318).
///
/// A process-lifetime session can silently go stale after sleep/wake or network
/// changes, so each lyrics fetch builds a new instance — and because sessions
/// must be explicitly invalidated to release their resources, this wrapper is a
/// class so `deinit` can call `finishTasksAndInvalidate()` when the call scope
/// releases it.
final class EphemeralSessionLRCLib {
    private let api: any LRCLib
    private let session: URLSession

    convenience init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: configuration)
        self.init(api: LRCLibAPI(provider: Provider(baseURL: LRCLibAPI.baseURL, urlSession: session)), session: session)
    }

    init(api: any LRCLib, session: URLSession) {
        self.api = api
        self.session = session
    }

    deinit {
        session.finishTasksAndInvalidate()
    }
}

extension EphemeralSessionLRCLib: LRCLib {
    func get(trackName: String, artistName: String, duration: Int?) async throws -> LyricsResult {
        try await api.get(trackName: trackName, artistName: artistName, duration: duration)
    }

    func search(q: String) async throws -> [LyricsResult] {
        try await api.search(q: q)
    }

    func healthCheck() async throws -> Response {
        try await api.healthCheck()
    }
}
