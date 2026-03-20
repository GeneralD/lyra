import AppKit
import ArgumentParser
import App
import Config
import Dependencies

struct DaemonCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "daemon",
        abstract: "Run the overlay in the foreground (internal use)",
        shouldDisplay: false
    )

    func run() {
        MainActor.assumeIsolated {
            let appConfig = ConfigLoader.shared.load()
            let resolvedConfig = appConfig.toAppStyle()

            withDependencies {
                $0.appStyle = resolvedConfig
            } operation: {
                let app = NSApplication.shared
                app.setActivationPolicy(.accessory)

                let delegate = AppDelegate()
                app.delegate = delegate

                app.run()
            }
        }
    }
}
