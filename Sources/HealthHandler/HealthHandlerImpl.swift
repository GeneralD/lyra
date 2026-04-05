import Dependencies
import Domain

public struct HealthHandlerImpl: HealthHandler {
    public init() {}

    public func check() async -> HealthReport {
        @Dependency(\.healthCheckers) var checkers

        let entries = await withTaskGroup(of: HealthReport.Entry.self, returning: [HealthReport.Entry].self) { group in
            for checker in checkers {
                group.addTask {
                    let result = await checker.healthCheck()
                    return HealthReport.Entry(serviceName: checker.serviceName, result: result)
                }
            }
            var results: [HealthReport.Entry] = []
            for await entry in group { results.append(entry) }
            return results
        }

        // Preserve original checker order
        let orderedNames = checkers.map(\.serviceName)
        let sorted = entries.sorted { a, b in
            (orderedNames.firstIndex(of: a.serviceName) ?? .max)
                < (orderedNames.firstIndex(of: b.serviceName) ?? .max)
        }
        return HealthReport(entries: sorted)
    }
}
