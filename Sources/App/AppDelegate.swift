import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var router: AppRouter?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let router = AppRouter()
        self.router = router
        Task {
            await router.start()
        }
        setupSignalHandlers()
    }

    private func setupSignalHandlers() {
        for signalType in [SIGTERM, SIGINT] {
            signal(signalType, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalType, queue: .main)
            source.setEventHandler { [weak self] in
                guard let self else { return }
                router?.stop()
                exit(0)
            }
            source.resume()
        }
    }
}
