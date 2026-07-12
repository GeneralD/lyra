import Foundation

/// Runs a single API call against a fresh, per-call ephemeral `URLSession` that is
/// invalidated the moment the call returns (#318).
///
/// A process-lifetime `URLSession` can silently go stale after sleep/wake or
/// network changes, leaving requests failing until the daemon restarts. Building
/// an ephemeral session per call sidesteps that, and invalidating it right after
/// the call releases its resources so per-call sessions don't accumulate in the
/// long-lived daemon.
///
/// The session is kept **function-local** inside ``withAPI(_:)`` — not stored
/// behind a class that invalidates in `deinit`. A stored-session/`deinit` design
/// is fragile: once the caller copies the wrapped client out, ARC may release the
/// owner (and invalidate the session) before the request is even issued. Keeping
/// the session local to the call, with a `defer`-based invalidation, makes the
/// lifetime unambiguous and the invalidation point explicit.
///
/// `makeAPI` receives the scoped session and builds the (Papyrus) client bound to
/// it; every per-API difference — base URL, auth headers, request shaping — lives
/// in that closure, so this type stays API-agnostic. Only the request timeout,
/// which legitimately varies per service, is a stored parameter.
public struct ScopedAPISession<API> {
    private let timeout: TimeInterval
    private let makeAPI: (URLSession) -> API

    public init(timeout: TimeInterval, makeAPI: @escaping (URLSession) -> API) {
        self.timeout = timeout
        self.makeAPI = makeAPI
    }

    public func withAPI<T>(_ body: (API) async throws -> T) async rethrows -> T {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        return try await body(makeAPI(session))
    }
}

// Safe: value type holding only an immutable timeout and an immutable factory
// closure; `withAPI` creates and tears down its own session with no shared state.
extension ScopedAPISession: @unchecked Sendable {}
