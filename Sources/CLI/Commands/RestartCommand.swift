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
        let result = try handler.restart()
        print(result.message)
        guard result.succeeded else { throw ExitCode.failure }
    }
}
