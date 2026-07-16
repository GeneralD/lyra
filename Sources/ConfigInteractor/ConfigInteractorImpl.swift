import Combine
import Dependencies
import Domain
import Foundation

/// Watches the config file's parent directory, debounces changes, then calls
/// `ConfigUseCase.reload()` and publishes the result.
///
/// The watch token and debounce task require mutable state, so this implementation
/// is a `final class` with `@unchecked Sendable`, as required by the Swift conventions.
public final class ConfigInteractorImpl: @unchecked Sendable {
    @Dependency(\.configWatchGateway) private var gateway
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
        // Watch the config directory whether or not the file exists yet, so a config
        // created after daemon start (`lyra config init`, a manual save) is picked up
        // as the initial load without a restart (#329). The gateway watches the
        // directory — not the file — for atomic-save rename resilience, so an absent
        // file inside an existing directory still arms correctly.
        let directory = configUseCase.configDir
        let watchedGateway = gateway
        lock.withLock {
            // Idempotent: a second start() (router restart, test harness, future
            // lifecycle changes) must not leak the previous DispatchSource/fd or
            // install a duplicate watch that would double-fire reload events.
            guard token == nil else { return }
            token = watchedGateway.watch(directory: directory) { [weak self] in self?.scheduleReload() }
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
