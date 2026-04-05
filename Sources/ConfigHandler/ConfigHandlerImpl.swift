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
            return .failure(.failed(detail: "Failed to write config file"))
        }
        return .success(.created(path: path))
    }

    public func configPath() -> ConfigPathResult {
        @Dependency(\.configUseCase) var configUseCase

        if let existing = configUseCase.existingConfigPath {
            return .success(.found(path: existing))
        }
        switch writeTemplate(format: .toml, force: false) {
        case .success(.created(let path)): return .success(.found(path: path))
        case .failure(let error): return .failure(error)
        }
    }
}
