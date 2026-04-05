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
        switch handler.start() {
        case .success(let s): output.output(s)
        case .failure(let e):
            output.output(e)
            throw ExitCode.failure
        }
    }
}
