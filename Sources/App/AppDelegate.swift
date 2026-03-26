import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var router: AppRouter?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let router = AppRouter()
        self.router = router
        router.start()

        for signalType in [SIGTERM, SIGINT] {
            signal(signalType, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalType, queue: .main)
            source.setEventHandler {
                router.stop()
                exit(0)
            }
            source.resume()
        }
    }
}
