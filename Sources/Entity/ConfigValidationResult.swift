public enum ConfigValidationResult {
    case loaded(path: String)
    case defaults
    case unreadable(path: String)
    case decodeError(path: String, error: String)
}

extension ConfigValidationResult: Sendable {}
