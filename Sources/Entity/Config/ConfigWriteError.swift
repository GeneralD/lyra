public enum ConfigWriteError: Error {
    case alreadyExists(path: String)
    case encodingFailed
}

extension ConfigWriteError: Sendable {}
