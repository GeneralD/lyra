import Dependencies
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

public protocol HealthCheckable: Sendable {
    var serviceName: String { get }
    func healthCheck() async -> HealthCheckResult
}

// MARK: - DependencyKey

public enum HealthCheckersKey: TestDependencyKey {
    public static let testValue: [any HealthCheckable] = []
}

extension DependencyValues {
    public var healthCheckers: [any HealthCheckable] {
        get { self[HealthCheckersKey.self] }
        set { self[HealthCheckersKey.self] = newValue }
    }
}
