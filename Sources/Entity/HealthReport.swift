public struct HealthReport: Sendable {
    public let entries: [Entry]

    public var failedCount: Int { entries.count { $0.result.status == .fail } }
    public var allPassed: Bool { failedCount == 0 }

    public init(entries: [Entry]) {
        self.entries = entries
    }

    public struct Entry: Sendable {
        public let serviceName: String
        public let result: HealthCheckResult

        public init(serviceName: String, result: HealthCheckResult) {
            self.serviceName = serviceName
            self.result = result
        }
    }
}
