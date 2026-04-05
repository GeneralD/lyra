import Dependencies
import Domain

public struct ConfigHandlerImpl: ConfigHandler {
    public init() {}

    public func template(format: ConfigFormat) -> String? {
        @Dependency(\.configUseCase) var configUseCase
        return configUseCase.template(format: format)
    }

    public func writeTemplate(format: ConfigFormat, force: Bool) -> ConfigWriteResult {
        @Dependency(\.configUseCase) var configUseCase
        guard let path = try? configUseCase.writeTemplate(format: format, force: force) else {
            return .failed(detail: "Failed to write config file")
        }
        return .created(path: path)
    }

    public func configPath() -> ConfigPathResult {
        @Dependency(\.configDataSource) var dataSource

        if let existing = dataSource.existingConfigPath() {
            return .found(path: existing)
        }
        switch writeTemplate(format: .toml, force: false) {
        case .created(let path): return .found(path: path)
        case .failed(let detail): return .failed(detail: detail)
        }
    }
}
