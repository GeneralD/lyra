import Dependencies

public protocol ConfigDataSource: Sendable {
    func load() -> ConfigLoadResult?
    func tryDecode() throws -> String
    func template(format: ConfigFormat) -> String?
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String
    func existingConfigPath() -> String?
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
    func tryDecode() throws -> String { "" }
    func template(format: ConfigFormat) -> String? { nil }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { "" }
    func existingConfigPath() -> String? { nil }
}
