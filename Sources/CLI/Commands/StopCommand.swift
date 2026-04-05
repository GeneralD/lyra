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
        switch handler.stop() {
        case .success(let s): output.output(s)
        case .failure(let e):
            output.output(e)
            throw ExitCode.failure
        }
    }
}
