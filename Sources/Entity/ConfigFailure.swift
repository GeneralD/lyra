public enum ConfigFailure: Error, Sendable, Equatable {
    case failed(detail: String)
}
