import Presentation
import Views

/// Wireframe: creates Presenters, builds window, manages lifecycle.
@MainActor
public final class AppRouter {
    private let appPresenter = AppPresenter()
    private let headerPresenter = HeaderPresenter()
    private let lyricsPresenter = LyricsPresenter()
    private let wallpaperPresenter = WallpaperPresenter()
    private var ripplePresenter: RipplePresenter!

    private var appWindow: AppWindow?
    private var displayLinkDriver: DisplayLinkDriver?

    public init() {}

    public func start() {
        appPresenter.start()
        ripplePresenter = RipplePresenter(screenOrigin: appPresenter.layout.screenOrigin)

        headerPresenter.start()
        lyricsPresenter.start()
        ripplePresenter.start()
        wallpaperPresenter.start()

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
    }

    public func stop() {
        headerPresenter.stop()
        lyricsPresenter.stop()
        wallpaperPresenter.stop()
        ripplePresenter.stop()
        displayLinkDriver?.stop()
        appWindow?.orderOut(nil)
        appWindow?.close()
        appWindow = nil
    }
}
