import Dependencies

public protocol HealthHandler: Sendable {
    func check() async -> HealthReport
}

public enum HealthHandlerKey: TestDependencyKey {
    public static let testValue: any HealthHandler = UnimplementedHealthHandler()
}

extension DependencyValues {
    public var healthHandler: any HealthHandler {
        get { self[HealthHandlerKey.self] }
        set { self[HealthHandlerKey.self] = newValue }
    }
}

private struct UnimplementedHealthHandler: HealthHandler {
    func check() async -> HealthReport { fatalError("HealthHandler.check not implemented") }
}
