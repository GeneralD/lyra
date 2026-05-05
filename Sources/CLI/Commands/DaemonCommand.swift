import App
import ArgumentParser
import Dependencies
import Domain

struct DaemonCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "daemon",
        abstract: "Run the overlay in the foreground (internal use)",
        shouldDisplay: false
    )

    func run() throws {
        @Dependency(\.foregroundApplicationRunner) var applicationRunner
        @Dependency(\.processHandler) var handler
        @Dependency(\.standardOutput) var output

        guard handler.acquireDaemonLock() else {
            output.write("Another lyra daemon is already running")
            throw ExitCode.failure
        }

        MainActor.assumeIsolated {
            applicationRunner.runAccessory()
        }
    }
}
