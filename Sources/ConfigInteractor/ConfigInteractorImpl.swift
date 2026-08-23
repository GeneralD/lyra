import Combine
import Dependencies
import Domain
import Foundation

/// Debounces config-change events from `ConfigUseCase.watchChanges(onChange:)`,
/// then calls `ConfigUseCase.reload()` and publishes the result. Which paths are
/// watched and how (directory vs file tiers, include resolution, re-arming) is
/// the DataSource layer's concern — this interactor only orchestrates reload
/// and publish.
///
/// The watch token and debounce task require mutable state, so this implementation
/// is a `final class` with `@unchecked Sendable`, as required by the Swift conventions.
public final class ConfigInteractorImpl: @unchecked Sendable {
    @Dependency(\.configUseCase) private var configUseCase
    @Dependency(\.continuousClock) private var clock

    private let appStyleSubject = PassthroughSubject<Void, Never>()
    private let invalidSubject = CurrentValueSubject<ConfigReloadFailure?, Never>(nil)
    private let lock = NSLock()
    private var token: (any ConfigWatchToken)?
    private var debounceTask: Task<Void, Never>?

    public init() {}

    deinit {
        token?.stop()
        debounceTask?.cancel()
    }
}

extension ConfigInteractorImpl: ConfigInteractor {
    public var appStyleChanges: AnyPublisher<Void, Never> { appStyleSubject.eraseToAnyPublisher() }
    public var invalidConfig: AnyPublisher<ConfigReloadFailure?, Never> { invalidSubject.eraseToAnyPublisher() }

    public func start() {
        lock.withLock {
            // Idempotent: a second start() (router restart, test harness, future
            // lifecycle changes) must not leak the previous watch or install a
            // duplicate one that would double-fire reload events.
            guard token == nil else { return }
            token = configUseCase.watchChanges { [weak self] in self?.scheduleReload() }
        }
    }

    public func stop() {
        lock.withLock {
            token?.stop()
            token = nil
            debounceTask?.cancel()
            debounceTask = nil
        }
    }

    // Debounce watch events to coalesce bursts and large writes before reloading.
    private func scheduleReload() {
        lock.withLock {
            debounceTask?.cancel()
            debounceTask = Task { [weak self, clock] in
                try? await clock.sleep(for: .milliseconds(150))
                self?.applyReload()
            }
        }
    }

    private func applyReload() {
        // Both teardown signals are checked under the same lock stop() takes, and
        // the reload + publishes stay inside it: a debounce task that already woke
        // can't slip a reload or a spurious UI update past a concurrent stop() —
        // once stop() returns, nothing further is emitted.
        //
        // Publishing while holding the lock is safe ONLY because every subscriber
        // hops off with `receive(on: DispatchQueue.main)` before doing work — a
        // synchronous subscriber could re-enter this interactor (or block) inside
        // the lock. Keep the main-queue hop when adding subscribers. Sending
        // outside the lock instead would reopen the post-stop() emission race
        // this block exists to close, so the hop is the chosen trade-off.
        lock.withLock {
            guard token != nil, !Task.isCancelled else { return }
            switch configUseCase.reload() {
            case .updated:
                invalidSubject.send(nil)
                appStyleSubject.send(())
            case .invalid(let failure):
                invalidSubject.send(failure)
            }
        }
    }
}
