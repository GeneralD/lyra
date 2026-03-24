import Dependencies

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
