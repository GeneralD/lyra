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
