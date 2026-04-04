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
        @Dependency(\.healthCheckers) var checkers

        var failed = 0
        for checker in checkers {
            let result = await checker.healthCheck()
            printResult(name: checker.serviceName, result: result)
            if case .fail = result.status { failed += 1 }
        }

        print("")
        guard failed == 0 else {
            print("\(failed) check(s) failed.")
            throw ExitCode.failure
        }
        print("All checks passed.")
    }
}

private func printResult(name: String, result: HealthCheckResult) {
    let tag: String
    switch result.status {
    case .pass: tag = "[PASS]"
    case .fail: tag = "[FAIL]"
    case .skip: tag = "[SKIP]"
    }
    print("\(tag) \(name.padding(toLength: 20, withPad: ".", startingAt: 0)) \(result.detail)")
}
