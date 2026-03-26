import AppKit
import Presentation
import Views

/// Wireframe: creates Presenters, resolves config, builds window, manages lifecycle.
@MainActor
public final class AppRouter {
    private let headerPresenter = HeaderPresenter()
    private let lyricsPresenter = LyricsPresenter()
    private let wallpaperPresenter = WallpaperPresenter()
    private let ripplePresenter = RipplePresenter()
    private let appPresenter = AppPresenter()

    private var appWindow: AppWindow?
    private var displayLinkDriver: DisplayLinkDriver?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    public init() {}

    public func start() async {
        headerPresenter.start()
        lyricsPresenter.start()
        ripplePresenter.start()
        await wallpaperPresenter.resolve()
        await appPresenter.resolveFrames(wallpaperURL: wallpaperPresenter.wallpaperURL)
        await wallpaperPresenter.setupPlayer()

        appWindow = AppWindow(
            appPresenter: appPresenter,
            wallpaperPresenter: wallpaperPresenter,
            headerPresenter: headerPresenter,
            lyricsPresenter: lyricsPresenter,
            ripplePresenter: ripplePresenter
        )

        let driver = DisplayLinkDriver { [weak self] in
            self?.ripplePresenter.idle()
            self?.lyricsPresenter.updateActiveLineTick()
        }
        self.displayLinkDriver = driver
        driver.start(in: appWindow!)

        observeSleepWake()
    }

    public func stop() {
        headerPresenter.stop()
        lyricsPresenter.stop()
        wallpaperPresenter.stop()
        ripplePresenter.stop()
        displayLinkDriver?.stop()
        removeSleepWakeObservers()
        appWindow?.orderOut(nil)
        appWindow?.close()
        appWindow = nil
    }
}

extension AppRouter {
    private func observeSleepWake() {
        let ws = NSWorkspace.shared.notificationCenter
        sleepObserver = ws.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.wallpaperPresenter.pause() }
        }
        wakeObserver = ws.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.wallpaperPresenter.play() }
        }
    }

    private func removeSleepWakeObservers() {
        let ws = NSWorkspace.shared.notificationCenter
        sleepObserver.map(ws.removeObserver)
        wakeObserver.map(ws.removeObserver)
    }
}
