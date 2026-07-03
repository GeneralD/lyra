import CoreGraphics
import Dependencies
import Domain
import Presenters
import Views

/// Wireframe: creates Presenters, builds window, manages lifecycle.
@MainActor
public final class AppRouter {
    private let bootstrap: AppDependencyBootstrap
    private let windowFactory:
        @MainActor (ScreenLayout, HeaderPresenter, LyricsPresenter, RipplePresenter, SpectrumPresenter, WallpaperPresenter)
            -> any OverlayWindow
    private let frameSchedulerFactory: @MainActor (@escaping @MainActor () -> Void) -> any FrameScheduler
    private var appPresenter: AppPresenter?
    private var headerPresenter: HeaderPresenter?
    private var lyricsPresenter: LyricsPresenter?
    private var wallpaperPresenter: WallpaperPresenter?
    private var ripplePresenter: RipplePresenter?
    private var spectrumPresenter: SpectrumPresenter?

    private var appWindow: (any OverlayWindow)?
    private var frameScheduler: (any FrameScheduler)?

    static func defaultFrameSchedulerFactory(
        onFrame: @escaping @MainActor () -> Void
    ) -> any FrameScheduler {
        DisplayLinkDriver(onFrame: onFrame)
    }

    public convenience init(launchEnvironment: AppLaunchEnvironment = .current) {
        self.init(
            bootstrap: AppDependencyBootstrap(launchEnvironment: launchEnvironment),
            windowFactory: { layout, headerPresenter, lyricsPresenter, ripplePresenter, spectrumPresenter, wallpaperPresenter in
                AppWindow(
                    initialLayout: layout,
                    headerPresenter: headerPresenter,
                    lyricsPresenter: lyricsPresenter,
                    ripplePresenter: ripplePresenter,
                    spectrumPresenter: spectrumPresenter,
                    wallpaperPresenter: wallpaperPresenter
                )
            },
            frameSchedulerFactory: Self.defaultFrameSchedulerFactory
        )
    }

    convenience init(
        launchEnvironment: AppLaunchEnvironment,
        windowFactory:
            @escaping @MainActor (
                ScreenLayout, HeaderPresenter, LyricsPresenter, RipplePresenter, SpectrumPresenter, WallpaperPresenter
            ) -> any OverlayWindow,
        frameSchedulerFactory: @escaping @MainActor (@escaping @MainActor () -> Void) -> any FrameScheduler
    ) {
        self.init(
            bootstrap: AppDependencyBootstrap(launchEnvironment: launchEnvironment),
            windowFactory: windowFactory,
            frameSchedulerFactory: frameSchedulerFactory
        )
    }

    init(
        bootstrap: AppDependencyBootstrap,
        windowFactory:
            @escaping @MainActor (
                ScreenLayout, HeaderPresenter, LyricsPresenter, RipplePresenter, SpectrumPresenter, WallpaperPresenter
            ) -> any OverlayWindow,
        frameSchedulerFactory: @escaping @MainActor (@escaping @MainActor () -> Void) -> any FrameScheduler
    ) {
        self.bootstrap = bootstrap
        self.windowFactory = windowFactory
        self.frameSchedulerFactory = frameSchedulerFactory
    }

    public func start() {
        guard appWindow == nil, frameScheduler == nil else { return }

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
            let spectrumPresenter = SpectrumPresenter()
            self.spectrumPresenter = spectrumPresenter

            headerPresenter.start()
            lyricsPresenter.start()
            ripplePresenter.start()
            spectrumPresenter.start()
            wallpaperPresenter.start()

            let window = windowFactory(
                layout, headerPresenter, lyricsPresenter, ripplePresenter, spectrumPresenter, wallpaperPresenter)
            appWindow = window
            window.show()

            appPresenter.bind(ripplePresenter: ripplePresenter)
            appPresenter.onWindowFrameChange { [weak window] layout in
                window?.applyLayout(layout)
            }
            wallpaperPresenter.onPlayerAvailable { [weak window, weak wallpaperPresenter] player in
                window?.attachPlayerLayer(for: player)
                window?.applyWallpaperScale(wallpaperPresenter?.wallpaperScale ?? 1.0)
            }
            wallpaperPresenter.onWallpaperScaleChange { [weak window] scale in
                window?.applyWallpaperScale(scale)
            }

            // Only enabled features pay a per-frame cost: each optional
            // handler is included in the frame fan-out only when its feature
            // is on, so a disabled ripple/spectrum adds zero work per tick.
            let frameHandlers: [@MainActor @Sendable () -> Void] = [
                ripplePresenter.isEnabled
                    ? { @MainActor @Sendable [weak self] in self?.ripplePresenter?.idle() } : nil,
                spectrumPresenter.isEnabled
                    ? { @MainActor @Sendable [weak self] in self?.spectrumPresenter?.tick() } : nil,
                { @MainActor @Sendable [weak self] in self?.lyricsPresenter?.updateActiveLineTick() },
            ].compactMap { $0 }
            let onFrame: @MainActor @Sendable () -> Void = {
                for handler in frameHandlers { handler() }
            }
            let scheduler = frameSchedulerFactory(onFrame)
            self.frameScheduler = scheduler
            scheduler.start(in: window)
        }
    }

    public func stop() {
        appPresenter?.stop()
        defer { appPresenter = nil }

        headerPresenter?.stop()
        defer { headerPresenter = nil }

        lyricsPresenter?.stop()
        defer { lyricsPresenter = nil }

        wallpaperPresenter?.stop()
        defer { wallpaperPresenter = nil }

        ripplePresenter?.stop()
        defer { ripplePresenter = nil }

        spectrumPresenter?.stop()
        defer { spectrumPresenter = nil }

        frameScheduler?.stop()
        defer { frameScheduler = nil }

        appWindow?.close()
        appWindow = nil
    }

    private func withBootstrap<T>(_ operation: () -> T) -> T {
        withDependencies {
            bootstrap.apply(to: &$0)
        } operation: {
            operation()
        }
    }
}
