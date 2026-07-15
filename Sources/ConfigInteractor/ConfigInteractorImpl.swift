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
        // Watch the parent directory only when the config file exists.
        guard let path = configUseCase.existingConfigPath else { return }
        let directory = (path as NSString).deletingLastPathComponent
        let watchedGateway = gateway
        lock.withLock {
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
                guard !Task.isCancelled else { return }
                self?.applyReload()
            }
        }
    }

    private func applyReload() {
        switch configUseCase.reload() {
        case .updated:
            invalidSubject.send(nil)
            appStyleSubject.send(())
        case .invalid(let failure):
            invalidSubject.send(failure)
        }
    }
}
