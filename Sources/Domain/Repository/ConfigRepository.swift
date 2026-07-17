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

extension ConfigRepository {
    public var configDir: String { "" }
    public var includedConfigPaths: [String] { [] }
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
