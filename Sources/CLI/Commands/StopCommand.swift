import ArgumentParser
import Dependencies
import Domain

struct StopCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Stop the running overlay"
    )

    func run() {
        @Dependency(\.processHandler) var handler

        switch handler.stop() {
        case .stopped:
            print("Stopped")
        case .notRunning:
            print("Not running")
        case .lockReleaseTimedOut:
            print("Stopped (warning: lock release timed out)")
        }
    }
}
