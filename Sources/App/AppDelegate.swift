import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var router: AppRouter?
    private var signalSources: [DispatchSourceSignal] = []

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let router = AppRouter()
        self.router = router
        router.start()

        signalSources = [SIGTERM, SIGINT].map { signalType in
            signal(signalType, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalType, queue: .main)
            source.setEventHandler {
                router.stop()
                exit(0)
            }
            source.resume()
            return source
        }
    }
}
