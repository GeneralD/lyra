import Dependencies

public protocol ConfigDataSource: Sendable {
    func load() -> ConfigLoadResult?
    /// Decodes the config to surface errors, returning the file path (or "" for defaults).
    /// - Parameter strictOptionalSections: when `true`, malformed `[ai]`/`[lyrics]`
    ///   sections also throw (used by `lyra healthcheck` to report them); when `false`,
    ///   they degrade to `nil` exactly as startup loading does, so only the required
    ///   structure gates validity (used by hot-reload).
    func tryDecode(strictOptionalSections: Bool) throws -> String
    func template(format: ConfigFormat) -> String?
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String
    var existingConfigPath: String? { get }
    var configDir: String { get }
    /// Resolved absolute paths of the config's `includes` files — additional
    /// hot-reload watch targets, re-resolved on every reload so an edited
    /// `includes` list retargets the watch. Defaults to empty; only the live
    /// implementation resolves real paths.
    var includedConfigPaths: [String] { get }
}

extension ConfigDataSource {
    public var includedConfigPaths: [String] { [] }
}

public enum ConfigDataSourceKey: TestDependencyKey {
    public static let testValue: any ConfigDataSource = UnimplementedConfigDataSource()
}

extension DependencyValues {
    public var configDataSource: any ConfigDataSource {
        get { self[ConfigDataSourceKey.self] }
        set { self[ConfigDataSourceKey.self] = newValue }
    }
}

private struct UnimplementedConfigDataSource: ConfigDataSource {
    func load() -> ConfigLoadResult? { nil }
    func tryDecode(strictOptionalSections: Bool) throws -> String { "" }
    func template(format: ConfigFormat) -> String? { nil }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { "" }
    var existingConfigPath: String? { nil }
    var configDir: String { "" }
}
