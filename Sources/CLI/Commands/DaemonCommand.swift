import App
import AppKit
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
        @Dependency(\.processHandler) var handler

        guard handler.acquireDaemonLock() else {
            print("Another lyra daemon is already running")
            throw ExitCode.failure
        }

        MainActor.assumeIsolated {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let delegate = AppDelegate()
            app.delegate = delegate
            _ = delegate  // retain until app.run() returns
            app.run()
        }
    }
}
