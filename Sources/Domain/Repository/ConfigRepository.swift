import Dependencies

public protocol ConfigRepository: Sendable {
    func loadAppStyle() -> AppStyle
    /// - Parameter strictOptionalSections: when `true`, malformed `[ai]`/`[lyrics]`
    ///   sections yield `.decodeError` (used by `lyra healthcheck`); when `false`,
    ///   they degrade to `nil` like startup, so only the required structure gates
    ///   validity (used by hot-reload).
    func validate(strictOptionalSections: Bool) -> ConfigValidationResult
    func template(format: ConfigFormat) -> String?
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String
    var existingConfigPath: String? { get }
    /// Arms the hot-reload watch over the whole config surface — the config
    /// directory, the config file, and its `includes` files — calling `onChange`
    /// on an arbitrary queue for every change until the returned token is
    /// stopped. Returns nil when the config directory cannot be watched.
    /// Defaults to nil; only the live implementation arms a real watch, so
    /// unrelated test stubs need not.
    func watchChanges(onChange: @escaping @Sendable () -> Void) -> (any ConfigWatchToken)?
}

extension ConfigRepository {
    public func watchChanges(onChange: @escaping @Sendable () -> Void) -> (any ConfigWatchToken)? { nil }
}

public enum ConfigRepositoryKey: TestDependencyKey {
    public static let testValue: any ConfigRepository = UnimplementedConfigRepository()
}

extension DependencyValues {
    public var configRepository: any ConfigRepository {
        get { self[ConfigRepositoryKey.self] }
        set { self[ConfigRepositoryKey.self] = newValue }
    }
}

private struct UnimplementedConfigRepository: ConfigRepository {
    func loadAppStyle() -> AppStyle { .init() }
    func validate(strictOptionalSections: Bool) -> ConfigValidationResult { .defaults }
    func template(format: ConfigFormat) -> String? { nil }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { "" }
    var existingConfigPath: String? { nil }
}
