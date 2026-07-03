import Dependencies
import Domain
import Foundation
import os

/// Multicasting repository over the single-consumer MediaRemote helper pipe.
///
/// `MediaRemoteDataSource.poll()` advances one shared iterator, so only one
/// poll loop may run per process. `stream()` therefore fans a single pump out
/// to any number of subscribers instead of starting a loop per call: the
/// first subscriber lazily starts the pump, every event is broadcast to all
/// live continuations, and a late subscriber immediately receives the last
/// seen value so it doesn't wait for the next helper tick (#23).
public final class NowPlayingRepositoryImpl: Sendable {
    /// Pump lifecycle. The `.starting` reservation guarantees at most one
    /// pump task ever exists — two tasks polling the shared iterator
    /// concurrently is unsafe — and its token lets the reserving call detect
    /// that an immediate EOF reset the hub before the task was stored:
    /// adopting the already-finished task there would block every future
    /// pump start.
    private enum Pump: Sendable {
        case idle
        case starting(UUID)
        case running(Task<Void, Never>)
    }

    private struct Hub: Sendable {
        var continuations: [UUID: AsyncStream<NowPlaying?>.Continuation] = [:]
        /// Last broadcast payload; `.some(nil)` means "session gone" was seen.
        var last: NowPlaying?? = nil
        var pump: Pump = .idle
    }

    private let dataSource: any MediaRemoteDataSource
    private let hub = OSAllocatedUnfairLock(initialState: Hub())

    public init() {
        @Dependency(\.mediaRemoteDataSource) var dataSource
        self.dataSource = dataSource
    }
}

extension NowPlayingRepositoryImpl: NowPlayingRepository {
    /// One-shot snapshot, routed through the same multicast pump: a direct
    /// `dataSource.poll()` here would compete with a running pump for the
    /// single helper iterator, so the snapshot is the first broadcast value
    /// instead — replayed immediately once the pump has seen one.
    public func fetch() async -> NowPlaying? {
        for await value in stream() { return value }
        return nil
    }

    public func stream() -> AsyncStream<NowPlaying?> {
        AsyncStream { continuation in
            let id = UUID()
            let replay = hub.withLock { state in
                state.continuations[id] = continuation
                return state.last
            }
            if let value = replay { continuation.yield(value) }
            continuation.onTermination = { [hub] _ in
                hub.withLock { $0.continuations[id] = nil }
            }
            ensurePumping()
        }
    }
}

extension NowPlayingRepositoryImpl {
    /// Starts the shared poll pump if it isn't running. The slot is reserved
    /// under the lock before the task is created outside it (task creation
    /// inside `withLock` trips region isolation), so a competing call can
    /// never spawn a second pump; the token check keeps a pump that hit EOF
    /// before being stored from occupying the freshly reset hub.
    private func ensurePumping() {
        let token = UUID()
        let reserved = hub.withLock { state in
            guard case .idle = state.pump else { return false }
            state.pump = .starting(token)
            return true
        }
        guard reserved else { return }
        let task = pumpTask()
        hub.withLock { state in
            guard case .starting(let current) = state.pump, current == token else {
                // The pump hit EOF and `finishAll()` reset the hub before
                // this store ran; the task is already finished, and the
                // fresh slot belongs to a future pump.
                task.cancel()
                return
            }
            state.pump = .running(task)
        }
    }

    private func pumpTask() -> Task<Void, Never> {
        Task {
            while !Task.isCancelled {
                switch await dataSource.poll() {
                case .info(let nowPlaying): broadcast(nowPlaying)
                case .noInfo: broadcast(nil)
                case .eof:
                    finishAll()
                    return
                }
            }
        }
    }

    private func broadcast(_ value: NowPlaying?) {
        let continuations = hub.withLock { state in
            state.last = .some(value)
            return Array(state.continuations.values)
        }
        for continuation in continuations { continuation.yield(value) }
    }

    /// The helper pipe hit EOF: finish every subscriber and reset the hub so
    /// a later subscriber starts a fresh pump (which will re-observe EOF).
    private func finishAll() {
        let continuations = hub.withLock { state in
            defer { state = Hub() }
            return Array(state.continuations.values)
        }
        for continuation in continuations { continuation.finish() }
    }
}
