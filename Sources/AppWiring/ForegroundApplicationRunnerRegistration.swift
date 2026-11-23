import App
import AppKit
import AppRouter
import Darwin
import Dependencies
import Domain

extension ForegroundApplicationRunnerKey: DependencyKey {
    public static let liveValue = ForegroundApplicationRunner {
        ForegroundApplication.runAccessory(
            backend: NSApplicationForegroundBackend(application: NSApplication.shared),
            delegateFactory: {
                AppDelegate(
                    routerFactory: { AppRouter() },
                    terminationHandler: SignalTerminationHandler(
                        signals: [SIGTERM, SIGINT],
                        backend: LiveSignalHandlingBackend(terminateProcess: { exit($0) })
                    )
                )
            }
        )
    }
}
