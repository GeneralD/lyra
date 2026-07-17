import Dependencies

public protocol ConfigUseCase: Sendable {
    var appStyle: AppStyle { get }
    func reload() -> ConfigReloadOutcome
    func template(format: ConfigFormat) -> String?
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String
    var existingConfigPath: String? { get }
    /// The directory the config file lives in, or would live in when absent —
    /// the hot-reload watch target (#329). Defaults to empty; only the live
    /// implementation resolves a real path, so unrelated test stubs need not.
    var configDir: String { get }
    /// Resolved absolute paths of the config's `includes` files — additional
    /// hot-reload watch targets, re-resolved on every reload so an edited
    /// `includes` list retargets the watch. Defaults to empty; only the live
    /// implementation resolves real paths.
    var includedConfigPaths: [String] { get }
}

extension ConfigUseCase {
    public var configDir: String { "" }
    public var includedConfigPaths: [String] { [] }
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
