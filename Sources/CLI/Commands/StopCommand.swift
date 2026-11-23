import ArgumentParser
import AsyncRunnableCommand
import Dependencies
import Domain

struct StopCommand: AsyncRunnableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Stop the running overlay"
    )

    func run() async throws {
        @Dependency(\.processHandler) var handler
        @Dependency(\.standardOutput) var output
        let result = await handler.stop()
        output.write(result)
        guard case .success = result else { throw ExitCode.failure }
    }
}
