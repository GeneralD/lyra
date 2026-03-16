import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlay: OverlayWindow?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let overlayWindow = OverlayWindow()
        overlayWindow.start()
        overlay = overlayWindow

        setupSignalHandlers()
    }

    private func setupSignalHandlers() {
        for signalType in [SIGTERM, SIGINT] {
            signal(signalType, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalType, queue: .main)
            source.setEventHandler { [weak self] in
                self?.overlay?.close()
                exit(0)
            }
            source.resume()
        }
    }
}
