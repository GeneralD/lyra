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
        @Dependency(\.standardOutput) var output
        let result = await handler.check()
        output.write(result)
        guard case .success = result else { throw ExitCode.failure }
    }
}
