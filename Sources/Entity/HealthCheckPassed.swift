public struct HealthCheckPassed: Sendable {
    public let entries: [HealthReportEntry]
    public init(entries: [HealthReportEntry]) { self.entries = entries }
}
