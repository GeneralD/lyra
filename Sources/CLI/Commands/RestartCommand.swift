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
        switch handler.restart() {
        case .success(let s): output.output(s)
        case .failure(let e):
            output.output(e)
            throw ExitCode.failure
        }
    }
}
