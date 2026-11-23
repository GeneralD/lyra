import ArgumentParser
import AsyncRunnableCommand
import Dependencies
import Domain

struct RestartCommand: AsyncRunnableCommand {
    static let configuration = CommandConfiguration(
        commandName: "restart",
        abstract: "Stop and start the overlay"
    )

    func run() async throws {
        @Dependency(\.processHandler) var handler
        @Dependency(\.standardOutput) var output
        let result = await handler.restart()
        output.write(result)
        guard case .success = result else { throw ExitCode.failure }
    }
}
