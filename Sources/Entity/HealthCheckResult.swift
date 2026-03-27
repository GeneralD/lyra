import Foundation

public struct HealthCheckResult {
    public enum Status {
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

extension HealthCheckResult: Sendable {}
extension HealthCheckResult.Status: Sendable {}
