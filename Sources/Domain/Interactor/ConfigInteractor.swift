import Combine
import Dependencies

/// Watches the config file for changes and publishes reload results.
///
/// Detects changes to the parent directory through `ConfigWatchGateway`, then calls
/// `ConfigUseCase.reload()` after debouncing. An `.updated` result becomes a Void ping
/// to Presenters through `appStyleChanges`; an `.invalid` result flows to the error
/// overlay through the latest-value `invalidConfig` stream.
public protocol ConfigInteractor: Sendable {
    /// Emits a Void ping when a reload applies a new AppStyle.
    var appStyleChanges: AnyPublisher<Void, Never> { get }
    /// The current invalid state. Nil means valid; non-nil means the previous value is retained.
    /// Replays the latest value.
    var invalidConfig: AnyPublisher<ConfigReloadFailure?, Never> { get }
    func start()
    func stop()
}

public enum ConfigInteractorKey: TestDependencyKey {
    public static let testValue: any ConfigInteractor = UnimplementedConfigInteractor()
}

extension DependencyValues {
    public var configInteractor: any ConfigInteractor {
        get { self[ConfigInteractorKey.self] }
        set { self[ConfigInteractorKey.self] = newValue }
    }
}

private struct UnimplementedConfigInteractor: ConfigInteractor {
    var appStyleChanges: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }
    var invalidConfig: AnyPublisher<ConfigReloadFailure?, Never> { Just(nil).eraseToAnyPublisher() }
    func start() {}
    func stop() {}
}
