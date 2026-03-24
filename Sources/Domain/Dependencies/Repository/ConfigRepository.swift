import Dependencies

public protocol ConfigRepository: Sendable {
    @MainActor func loadAppStyle() -> AppStyle
    func validate() -> ConfigValidationResult
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
    @MainActor func loadAppStyle() -> AppStyle { .init() }
    func validate() -> ConfigValidationResult { .defaults }
}
