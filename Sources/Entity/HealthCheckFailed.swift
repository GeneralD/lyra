public struct HealthCheckFailed: Error, Sendable {
    public let entries: [HealthReportEntry]
    public var failedCount: Int { entries.count { $0.result.status == .fail } }
    public init(entries: [HealthReportEntry]) { self.entries = entries }
}
