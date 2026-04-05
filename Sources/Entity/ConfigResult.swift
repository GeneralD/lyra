public enum ConfigWriteResult: Sendable {
    case created(path: String)
    case failed(detail: String)

    public var message: String {
        switch self {
        case .created(let path): "Config file created at \(path)"
        case .failed(let detail): "Config error: \(detail)"
        }
    }

    public var succeeded: Bool {
        guard case .created = self else { return false }
        return true
    }
}

public enum ConfigPathResult: Sendable {
    case found(path: String)
    case failed(detail: String)

    public var message: String {
        switch self {
        case .found(let path): path
        case .failed(let detail): "Config error: \(detail)"
        }
    }

    public var succeeded: Bool {
        guard case .found = self else { return false }
        return true
    }
}
