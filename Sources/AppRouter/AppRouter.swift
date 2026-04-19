import CoreGraphics
import Dependencies
import Presenters
import Views

/// Wireframe: creates Presenters, builds window, manages lifecycle.
@MainActor
public final class AppRouter {
    private let bootstrap: AppDependencyBootstrap
    private let windowFactory: @MainActor (AppPresenter, WallpaperPresenter, HeaderPresenter, LyricsPresenter, RipplePresenter) -> any AppWindowing
    private let displayLinkDriverFactory: @MainActor (@escaping @MainActor () -> Void) -> any DisplayLinkDriving
    private var appPresenter: AppPresenter?
    private var headerPresenter: HeaderPresenter?
    private var lyricsPresenter: LyricsPresenter?
    private var wallpaperPresenter: WallpaperPresenter?
    private var ripplePresenter: RipplePresenter?

    private var appWindow: (any AppWindowing)?
    private var displayLinkDriver: (any DisplayLinkDriving)?

    public convenience init(launchEnvironment: AppLaunchEnvironment = .current) {
        self.init(
            launchEnvironment: launchEnvironment,
            windowFactory: { appPresenter, wallpaperPresenter, headerPresenter, lyricsPresenter, ripplePresenter in
                AppWindow(
                    appPresenter: appPresenter,
                    wallpaperPresenter: wallpaperPresenter,
                    headerPresenter: headerPresenter,
                    lyricsPresenter: lyricsPresenter,
                    ripplePresenter: ripplePresenter
                )
            },
            displayLinkDriverFactory: { onFrame in
                DisplayLinkDriver(onFrame: onFrame)
            }
        )
    }

    init(
        launchEnvironment: AppLaunchEnvironment,
        windowFactory: @escaping @MainActor (AppPresenter, WallpaperPresenter, HeaderPresenter, LyricsPresenter, RipplePresenter) -> any AppWindowing,
        displayLinkDriverFactory: @escaping @MainActor (@escaping @MainActor () -> Void) -> any DisplayLinkDriving
    ) {
        self.bootstrap = AppDependencyBootstrap(launchEnvironment: launchEnvironment)
        self.windowFactory = windowFactory
        self.displayLinkDriverFactory = displayLinkDriverFactory
    }

    public func start() {
        guard appWindow == nil, displayLinkDriver == nil else { return }

        withBootstrap {
            let appPresenter = AppPresenter()
            let headerPresenter = HeaderPresenter()
            let lyricsPresenter = LyricsPresenter()
            let wallpaperPresenter = WallpaperPresenter()
            self.appPresenter = appPresenter
            self.headerPresenter = headerPresenter
            self.lyricsPresenter = lyricsPresenter
            self.wallpaperPresenter = wallpaperPresenter

            appPresenter.start()
            let layout = appPresenter.layout
            let ripplePresenter = RipplePresenter(
                screenRect: CGRect(origin: layout.screenOrigin, size: layout.hostingFrame.size))
            self.ripplePresenter = ripplePresenter

            headerPresenter.start()
            lyricsPresenter.start()
            ripplePresenter.start()
            wallpaperPresenter.start()

            let window = windowFactory(
                appPresenter,
                wallpaperPresenter,
                headerPresenter,
                lyricsPresenter,
                ripplePresenter
            )
            appWindow = window

            let driver = displayLinkDriverFactory { [weak self] in
                self?.ripplePresenter?.idle()
                self?.lyricsPresenter?.updateActiveLineTick()
            }
            self.displayLinkDriver = driver
            driver.start(in: window)
        }
    }

    public func stop() {
        guard appWindow != nil || displayLinkDriver != nil else { return }

        headerPresenter?.stop()
        lyricsPresenter?.stop()
        wallpaperPresenter?.stop()
        ripplePresenter?.stop()
        displayLinkDriver?.stop()
        appWindow?.orderOut(nil)
        appWindow?.close()
        displayLinkDriver = nil
        appWindow = nil
        ripplePresenter = nil
        wallpaperPresenter = nil
        lyricsPresenter = nil
        headerPresenter = nil
        appPresenter = nil
    }

    private func withBootstrap<T>(_ operation: () -> T) -> T {
        withDependencies {
            bootstrap.apply(to: &$0)
        } operation: {
            operation()
        }
    }
}
