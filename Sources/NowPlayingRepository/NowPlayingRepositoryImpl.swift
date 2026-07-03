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
    private struct Hub: Sendable {
        var continuations: [UUID: AsyncStream<NowPlaying?>.Continuation] = [:]
        /// Last broadcast payload; `.some(nil)` means "session gone" was seen.
        var last: NowPlaying?? = nil
        var pump: Task<Void, Never>?
    }

    private let dataSource: any MediaRemoteDataSource
    private let hub = OSAllocatedUnfairLock(initialState: Hub())

    public init() {
        @Dependency(\.mediaRemoteDataSource) var dataSource
        self.dataSource = dataSource
    }
}

extension NowPlayingRepositoryImpl: NowPlayingRepository {
    public func fetch() async -> NowPlaying? {
        switch await dataSource.poll() {
        case .info(let nowPlaying): nowPlaying
        case .noInfo, .eof: nil
        }
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
    /// Starts the shared poll pump if it isn't running. The candidate task is
    /// created outside the lock (task creation inside `withLock` trips region
    /// isolation); a lost creation race is cancelled, and since every pump
    /// broadcasts to all continuations, the overlap window loses no events.
    private func ensurePumping() {
        guard hub.withLock({ $0.pump == nil }) else { return }
        let candidate = pumpTask()
        let adopted = hub.withLock { state in
            guard state.pump == nil else { return false }
            state.pump = candidate
            return true
        }
        guard adopted else {
            candidate.cancel()
            return
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
