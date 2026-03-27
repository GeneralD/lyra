import Foundation

public enum ConfigWriteError: LocalizedError {
    case alreadyExists(path: String)
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .alreadyExists(let path): "Config file already exists at \(path). Use --force to overwrite."
        case .encodingFailed: "Failed to encode config template."
        }
    }
}
