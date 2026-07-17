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
    /// Arms the hot-reload watch over the whole config surface — the config
    /// directory (so a file created after daemon start is picked up, #329),
    /// the config file and its `includes` files (in-place overwrites), and the
    /// parent directories of includes living outside the config directory —
    /// calling `onChange` on an arbitrary queue for every change until the
    /// returned token is stopped. The watched set is resolved (and re-armed)
    /// from the on-disk config by the implementation, so it can never drift
    /// from what decode actually merges. A config directory that does not
    /// exist yet parks the watch on its nearest existing ancestor and promotes
    /// it once the directory appears, firing `onChange` as the initial load
    /// (#338) — so nil is returned only when nothing on that chain is
    /// watchable either. Defaults to nil; only the live implementation arms a
    /// real watch, so unrelated test stubs need not.
    func watchChanges(onChange: @escaping @Sendable () -> Void) -> (any ConfigWatchToken)?
}

extension ConfigDataSource {
    public func watchChanges(onChange: @escaping @Sendable () -> Void) -> (any ConfigWatchToken)? { nil }
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
