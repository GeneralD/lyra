import Dependencies

public protocol ConfigHandler: Sendable {
    func template(format: ConfigFormat) -> String?
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String
    func configPath() throws -> String
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
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String {
        fatalError("ConfigHandler.writeTemplate not implemented")
    }
    func configPath() throws -> String { fatalError("ConfigHandler.configPath not implemented") }
}
