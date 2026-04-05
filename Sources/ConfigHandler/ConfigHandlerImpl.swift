import Dependencies
import Domain

public struct ConfigHandlerImpl: ConfigHandler {
    public init() {}

    public func template(format: ConfigFormat) -> String? {
        @Dependency(\.configUseCase) var configUseCase
        return configUseCase.template(format: format)
    }

    public func writeTemplate(format: ConfigFormat, force: Bool) throws -> String {
        @Dependency(\.configUseCase) var configUseCase
        return try configUseCase.writeTemplate(format: format, force: force)
    }

    public func configPath() throws -> String {
        @Dependency(\.configDataSource) var dataSource

        if let existing = dataSource.existingConfigPath() {
            return existing
        }
        return try writeTemplate(format: .toml, force: false)
    }
}
