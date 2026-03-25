import Foundation

public struct ConfigLoadResult {
    public let config: AppConfig
    public let configDir: String
    public let path: String

    public init(config: AppConfig, configDir: String, path: String) {
        self.config = config
        self.configDir = configDir
        self.path = path
    }
}

extension ConfigLoadResult: Sendable {}
