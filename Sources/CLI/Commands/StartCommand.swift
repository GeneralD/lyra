import ArgumentParser
import AsyncRunnableCommand
import Dependencies
import Domain

struct StartCommand: AsyncRunnableCommand {
    static let configuration = CommandConfiguration(
        commandName: "start",
        abstract: "Start the overlay as a background process"
    )

    func run() async throws {
        @Dependency(\.processHandler) var handler
        @Dependency(\.standardOutput) var output
        let result = await handler.start()
        output.write(result)
        guard case .success = result else { throw ExitCode.failure }
    }
}
