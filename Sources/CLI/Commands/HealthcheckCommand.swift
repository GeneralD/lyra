import ArgumentParser
import AsyncRunnableCommand
import Dependencies
import Domain

struct HealthcheckCommand: AsyncRunnableCommand {
    static let configuration = CommandConfiguration(
        commandName: "healthcheck",
        abstract: "Check connectivity to external services"
    )

    func run() async throws {
        @Dependency(\.healthHandler) var handler
        let report = await handler.check()

        for entry in report.entries {
            let tag: String
            switch entry.result.status {
            case .pass: tag = "[PASS]"
            case .fail: tag = "[FAIL]"
            case .skip: tag = "[SKIP]"
            }
            print("\(tag) \(entry.serviceName.padding(toLength: 20, withPad: ".", startingAt: 0)) \(entry.result.detail)")
        }

        print("")
        guard report.allPassed else {
            print("\(report.failedCount) check(s) failed.")
            throw ExitCode.failure
        }
        print("All checks passed.")
    }
}
