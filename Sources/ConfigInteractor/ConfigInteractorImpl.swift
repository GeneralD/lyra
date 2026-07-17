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
    private var rearmedTokens: [any ConfigWatchToken] = []
    private var debounceTask: Task<Void, Never>?

    public init() {}

    deinit {
        token?.stop()
        for rearmed in rearmedTokens { rearmed.stop() }
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
            armFileWatchLocked()
        }
    }

    public func stop() {
        lock.withLock {
            token?.stop()
            token = nil
            for rearmed in rearmedTokens { rearmed.stop() }
            rearmedTokens = []
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
            // An atomic save renamed a fresh inode into place (killing the old
            // file fd), or the file just appeared for the first time (#329) —
            // re-arm the file-level watch on the current path so the next
            // in-place overwrite is still observed.
            armFileWatchLocked()
        }
    }

    /// Arms file-level watches on the config file and its `includes` files
    /// (no-ops for paths that do not exist). The directory watch alone misses
    /// in-place overwrites — editors that save without renaming, `cp`, appends —
    /// because a directory vnode only fires on entry changes. Includes living
    /// outside `configDir` additionally get their parent directory watched, so
    /// an atomic save there (which kills the file fd without firing the config
    /// directory watch) still triggers a reload. Caller must hold `lock`.
    private func armFileWatchLocked() {
        for rearmed in rearmedTokens { rearmed.stop() }
        let includes = configUseCase.includedConfigPaths
        let files = [configUseCase.existingConfigPath].compactMap { $0 } + includes
        let foreignDirectories = Set(includes.map { ($0 as NSString).deletingLastPathComponent })
            .subtracting([configUseCase.configDir])
        rearmedTokens =
            files.compactMap { path in
                gateway.watch(file: path) { [weak self] in self?.scheduleReload() }
            }
            + foreignDirectories.compactMap { directory in
                gateway.watch(directory: directory) { [weak self] in self?.scheduleReload() }
            }
    }
}
