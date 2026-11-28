public struct HealthReportEntry: Sendable {
    public let serviceName: String
    public let result: HealthCheckResult
    public init(serviceName: String, result: HealthCheckResult) {
        self.serviceName = serviceName
        self.result = result
    }
}
