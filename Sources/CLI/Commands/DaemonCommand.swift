import AppKit
import ArgumentParser
import App
import Dependencies

struct DaemonCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "daemon",
        abstract: "Run the overlay in the foreground (internal use)",
        shouldDisplay: false
    )

    func run() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)

            let delegate = AppDelegate()
            app.delegate = delegate

            app.run()
        }
    }
}
