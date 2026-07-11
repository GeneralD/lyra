import Domain
import Foundation
@preconcurrency import Papyrus

/// A call-scoped MusicBrainz client owning a fresh ephemeral `URLSession` (#318).
///
/// Same session strategy as `EphemeralSessionLRCLib`: fresh connections per
/// call, with `deinit` invalidating the session so per-call sessions don't
/// accumulate in the long-lived daemon.
final class EphemeralSessionMusicBrainz {
    private let api: any MusicBrainz
    private let session: URLSession

    convenience init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: configuration)
        self.init(api: MusicBrainzAPI(provider: Provider(baseURL: MusicBrainzAPI.baseURL, urlSession: session)), session: session)
    }

    init(api: any MusicBrainz, session: URLSession) {
        self.api = api
        self.session = session
    }

    deinit {
        session.finishTasksAndInvalidate()
    }
}

extension EphemeralSessionMusicBrainz: MusicBrainz {
    func searchRecording(query: String, fmt: String, limit: Int) async throws -> MusicBrainzResponse {
        try await api.searchRecording(query: query, fmt: fmt, limit: limit)
    }

    func healthCheck() async throws -> Response {
        try await api.healthCheck()
    }
}
