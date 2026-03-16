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
            let appConfig = AppConfig.load()
            let resolvedConfig = appConfig.toResolvedConfig()

            withDependencies {
                $0.config = resolvedConfig
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
