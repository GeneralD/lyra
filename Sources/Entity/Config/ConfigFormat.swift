public enum ConfigFormat: String {
    case toml
    case json

    public var fileExtension: String { rawValue }
}

extension ConfigFormat: CaseIterable {}
extension ConfigFormat: Sendable {}
