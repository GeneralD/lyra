import ArgumentParser
import Dependencies
import Domain

struct StopCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Stop the running overlay"
    )

    func run() throws {
        @Dependency(\.processHandler) var handler
        @Dependency(\.standardOutput) var output
        let result = handler.stop()
        output.write(result)
        guard case .success = result else { throw ExitCode.failure }
    }
}
