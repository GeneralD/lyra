import Dependencies

public protocol ConfigUseCase: Sendable {
    @MainActor func loadAppStyle() -> AppStyle
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
    @MainActor func loadAppStyle() -> AppStyle { .init() }
}
