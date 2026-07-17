import Dependencies

public protocol ConfigUseCase: Sendable {
    var appStyle: AppStyle { get }
    func reload() -> ConfigReloadOutcome
    func template(format: ConfigFormat) -> String?
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String
    var existingConfigPath: String? { get }
    /// Arms the hot-reload watch over the whole config surface — the config
    /// directory, the config file, and its `includes` files — calling `onChange`
    /// on an arbitrary queue for every change until the returned token is
    /// stopped. Which paths are watched and how is the DataSource layer's
    /// concern. Returns nil when the config directory cannot be watched.
    /// Defaults to nil; only the live implementation arms a real watch, so
    /// unrelated test stubs need not.
    func watchChanges(onChange: @escaping @Sendable () -> Void) -> (any ConfigWatchToken)?
}

extension ConfigUseCase {
    public func watchChanges(onChange: @escaping @Sendable () -> Void) -> (any ConfigWatchToken)? { nil }
}

public enum ConfigUseCaseKey: TestDependencyKey {
    public static let testValue: any ConfigUseCase = UnimplementedConfigUseCase()
}

extension DependencyValues {
    public var configUseCase: any ConfigUseCase {
        get { self[ConfigUseCaseKey.self] }
        set { self[ConfigUseCaseKey.self] = newValue }
    }
}

private struct UnimplementedConfigUseCase: ConfigUseCase {
    var appStyle: AppStyle { .init() }
    func reload() -> ConfigReloadOutcome { .updated(.init()) }
    func template(format: ConfigFormat) -> String? { nil }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { "" }
    var existingConfigPath: String? { nil }
}
