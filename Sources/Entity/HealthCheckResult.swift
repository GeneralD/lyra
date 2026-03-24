import Foundation

public struct HealthCheckResult: Sendable {
    public enum Status: Sendable {
        case pass
        case fail
        case skip
    }

    public let status: Status
    public let detail: String
    public let latency: TimeInterval?

    public init(status: Status, detail: String, latency: TimeInterval? = nil) {
        self.status = status
        self.detail = detail
        self.latency = latency
    }
}
