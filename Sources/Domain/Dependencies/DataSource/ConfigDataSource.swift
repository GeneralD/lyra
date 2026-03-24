import Dependencies

public protocol ConfigDataSource: Sendable {
    func load() -> ConfigLoadResult?
    func tryDecode() throws -> String
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
}
