public typealias HealthCheckReport = Result<HealthCheckPassed, HealthCheckFailed>

public struct HealthCheckPassed: Sendable {
    public let entries: [HealthReportEntry]
    public init(entries: [HealthReportEntry]) { self.entries = entries }
}

public struct HealthCheckFailed: Error, Sendable {
    public let entries: [HealthReportEntry]
    public var failedCount: Int { entries.count { $0.result.status == .fail } }
    public init(entries: [HealthReportEntry]) { self.entries = entries }
}

public struct HealthReportEntry: Sendable {
    public let serviceName: String
    public let result: HealthCheckResult
    public init(serviceName: String, result: HealthCheckResult) {
        self.serviceName = serviceName
        self.result = result
    }
}
