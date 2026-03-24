import Dependencies
import Domain

public struct ConfigUseCaseImpl {
    @Dependency(\.configRepository) private var repository

    public init() {}
}

extension ConfigUseCaseImpl: ConfigUseCase {
    @MainActor
    public func loadAppStyle() -> AppStyle {
        repository.loadAppStyle()
    }
}

extension ConfigUseCaseKey: DependencyKey {
    public static let liveValue: any ConfigUseCase = ConfigUseCaseImpl()
}
