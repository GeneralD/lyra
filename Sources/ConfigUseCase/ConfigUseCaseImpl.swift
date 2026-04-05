import Dependencies
import Domain

public final class ConfigUseCaseImpl: @unchecked Sendable {
    @Dependency(\.configRepository) private var repository
    private lazy var cachedAppStyle: AppStyle = repository.loadAppStyle()

    public init() {}
}

extension ConfigUseCaseImpl: ConfigUseCase {
    public var appStyle: AppStyle { cachedAppStyle }

    public func template(format: ConfigFormat) -> String? {
        repository.template(format: format)
    }

    public func writeTemplate(format: ConfigFormat, force: Bool) throws -> String {
        try repository.writeTemplate(format: format, force: force)
    }

    public var existingConfigPath: String? {
        repository.existingConfigPath
    }
}
