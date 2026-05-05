public struct ConfigLoadResult {
    public let config: AppConfig
    public let configDir: String

    public init(config: AppConfig, configDir: String) {
        self.config = config
        self.configDir = configDir
    }
}

extension ConfigLoadResult: Sendable {}
