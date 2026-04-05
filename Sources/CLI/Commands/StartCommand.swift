import ArgumentParser
import Dependencies
import Domain

struct StartCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "start",
        abstract: "Start the overlay as a background process"
    )

    func run() throws {
        @Dependency(\.processHandler) var handler
        @Dependency(\.standardOutput) var output
        let result = handler.start()
        output.write(result)
        guard case .success = result else { throw ExitCode.failure }
    }
}
