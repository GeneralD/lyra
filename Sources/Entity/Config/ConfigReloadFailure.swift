public struct ConfigReloadFailure {
    public enum Reason {
        case unreadable
        case decode(String)
    }

    public let path: String
    public let reason: Reason

    public init(path: String, reason: Reason) {
        self.path = path
        self.reason = reason
    }
}

extension ConfigReloadFailure.Reason: Sendable {}
extension ConfigReloadFailure.Reason: Equatable {}
extension ConfigReloadFailure: Sendable {}
extension ConfigReloadFailure: Equatable {}
