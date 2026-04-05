import Dependencies
import Domain

public struct HealthHandlerImpl: HealthHandler {
    public init() {}

    public func check() async -> HealthCheckReport {
        @Dependency(\.healthCheckers) var checkers
        let checkerList = checkers

        let entries = await withTaskGroup(
            of: (Int, HealthReportEntry).self,
            returning: [HealthReportEntry].self
        ) { group in
            for (index, checker) in checkerList.enumerated() {
                group.addTask {
                    let result = await checker.healthCheck()
                    return (index, HealthReportEntry(serviceName: checker.serviceName, result: result))
                }
            }
            var results: [(Int, HealthReportEntry)] = []
            for await pair in group { results.append(pair) }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }

        let hasFailed = entries.contains { $0.result.status == .fail }
        return hasFailed
            ? .failure(HealthCheckFailed(entries: entries))
            : .success(HealthCheckPassed(entries: entries))
    }
}
