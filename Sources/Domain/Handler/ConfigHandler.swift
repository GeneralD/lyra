import Dependencies

public protocol ConfigHandler: Sendable {
    func template(format: ConfigFormat) -> String?
    func writeTemplate(format: ConfigFormat, force: Bool) -> ConfigWriteResult
    func configPath() -> ConfigPathResult
    func editConfig() -> ConfigLaunchResult
    func openConfig() -> ConfigLaunchResult
}

extension ConfigHandler {
    public func editConfig() -> ConfigLaunchResult {
        .failure(.failed(detail: "Config edit is not supported"))
    }

    public func openConfig() -> ConfigLaunchResult {
        .failure(.failed(detail: "Config open is not supported"))
    }
}

public enum ConfigHandlerKey: TestDependencyKey {
    public static let testValue: any ConfigHandler = UnimplementedConfigHandler()
}

extension DependencyValues {
    public var configHandler: any ConfigHandler {
        get { self[ConfigHandlerKey.self] }
        set { self[ConfigHandlerKey.self] = newValue }
    }
}

private struct UnimplementedConfigHandler: ConfigHandler {
    func template(format: ConfigFormat) -> String? { fatalError("ConfigHandler.template not implemented") }
    func writeTemplate(format: ConfigFormat, force: Bool) -> ConfigWriteResult {
        fatalError("ConfigHandler.writeTemplate not implemented")
    }
    func configPath() -> ConfigPathResult { fatalError("ConfigHandler.configPath not implemented") }
    func editConfig() -> ConfigLaunchResult { fatalError("ConfigHandler.editConfig not implemented") }
    func openConfig() -> ConfigLaunchResult { fatalError("ConfigHandler.openConfig not implemented") }
}
