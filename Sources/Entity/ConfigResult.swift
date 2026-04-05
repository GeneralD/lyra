public typealias ConfigWriteResult = Result<ConfigWriteSuccess, ConfigFailure>
public typealias ConfigPathResult = Result<ConfigPathSuccess, ConfigFailure>

public enum ConfigWriteSuccess: Sendable, Equatable {
    case created(path: String)
}

public enum ConfigPathSuccess: Sendable, Equatable {
    case found(path: String)
}

public enum ConfigFailure: Error, Sendable, Equatable {
    case failed(detail: String)
}
