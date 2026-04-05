import ArgumentParser
import Dependencies
import Domain

struct RestartCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "restart",
        abstract: "Stop and start the overlay"
    )

    func run() throws {
        @Dependency(\.processHandler) var handler
        @Dependency(\.standardOutput) var output
        let result = handler.restart()
        output.write(result)
        guard case .success = result else { throw ExitCode.failure }
    }
}
