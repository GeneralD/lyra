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
        @MainActor (
            ScreenLayout, HeaderPresenter, LyricsPresenter, RipplePresenter, SpectrumPresenter, WallpaperPresenter,
            ConfigStatusPresenter?
        )
            -> any OverlayWindow
    private let frameSchedulerFactory: @MainActor (@escaping @MainActor (Double) -> Void) -> any FrameScheduler
    private var appPresenter: AppPresenter?
    private var headerPresenter: HeaderPresenter?
    private var lyricsPresenter: LyricsPresenter?
    private var wallpaperPresenter: WallpaperPresenter?
    private var ripplePresenter: RipplePresenter?
    private var spectrumPresenter: SpectrumPresenter?
    private var configStatusPresenter: ConfigStatusPresenter?

    private var appWindow: (any OverlayWindow)?
    private var frameScheduler: (any FrameScheduler)?

    static func defaultFrameSchedulerFactory(
        onFrame: @escaping @MainActor (Double) -> Void
    ) -> any FrameScheduler {
        DisplayLinkDriver(onFrame: onFrame)
    }

    static func defaultWindowFactory(
        layout: ScreenLayout,
        headerPresenter: HeaderPresenter,
        lyricsPresenter: LyricsPresenter,
        ripplePresenter: RipplePresenter,
        spectrumPresenter: SpectrumPresenter,
        wallpaperPresenter: WallpaperPresenter,
        configStatusPresenter: ConfigStatusPresenter?
    ) -> any OverlayWindow {
        AppWindow(
            initialLayout: layout,
            headerPresenter: headerPresenter,
            lyricsPresenter: lyricsPresenter,
            ripplePresenter: ripplePresenter,
            spectrumPresenter: spectrumPresenter,
            wallpaperPresenter: wallpaperPresenter,
            configStatusPresenter: configStatusPresenter
        )
    }

    public convenience init(launchEnvironment: AppLaunchEnvironment = .current) {
        self.init(
            bootstrap: AppDependencyBootstrap(launchEnvironment: launchEnvironment),
            windowFactory: Self.defaultWindowFactory,
            frameSchedulerFactory: Self.defaultFrameSchedulerFactory
        )
    }

    convenience init(
        launchEnvironment: AppLaunchEnvironment,
        windowFactory:
            @escaping @MainActor (
                ScreenLayout, HeaderPresenter, LyricsPresenter, RipplePresenter, SpectrumPresenter, WallpaperPresenter,
                ConfigStatusPresenter?
            ) -> any OverlayWindow,
        frameSchedulerFactory: @escaping @MainActor (@escaping @MainActor (Double) -> Void) -> any FrameScheduler
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
                ScreenLayout, HeaderPresenter, LyricsPresenter, RipplePresenter, SpectrumPresenter, WallpaperPresenter,
                ConfigStatusPresenter?
            ) -> any OverlayWindow,
        frameSchedulerFactory: @escaping @MainActor (@escaping @MainActor (Double) -> Void) -> any FrameScheduler
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
            let configStatusPresenter = ConfigStatusPresenter()
            self.configStatusPresenter = configStatusPresenter

            headerPresenter.start()
            lyricsPresenter.start()
            ripplePresenter.start()
            spectrumPresenter.start()
            wallpaperPresenter.start()
            // ConfigStatusPresenter owns the ConfigInteractor lifecycle
            // (arming the config-file watch); it is started last so every
            // `appStyleChanges` subscriber above is live before the initial
            // reload fires.
            configStatusPresenter.start()

            let window = windowFactory(
                layout, headerPresenter, lyricsPresenter, ripplePresenter, spectrumPresenter, wallpaperPresenter,
                configStatusPresenter)
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
            wallpaperPresenter.onPlayerCleared { [weak window] in
                window?.detachPlayerLayer()
            }
            wallpaperPresenter.onWallpaperScaleChange { [weak window] scale in
                window?.applyWallpaperScale(scale)
            }

            // Ripple and spectrum handlers are always installed so enabling either
            // at runtime resumes its per-frame work without rebuilding the fan-out
            // (#41 PR3). Each bails cheaply while its feature is inactive —
            // `idle()` on an enabled guard, `tick()` on its capturing/residue guard
            // — so a disabled feature still adds no real per-frame cost (#252/#258).
            let frameHandlers: [@MainActor @Sendable (Double) -> Void] = [
                { @MainActor @Sendable [weak self] _ in self?.ripplePresenter?.idle() },
                { @MainActor @Sendable [weak self] interval in
                    self?.spectrumPresenter?.tick(frameInterval: interval)
                },
                { @MainActor @Sendable [weak self] _ in self?.lyricsPresenter?.updateActiveLineTick() },
            ]
            let onFrame: @MainActor @Sendable (Double) -> Void = { interval in
                for handler in frameHandlers { handler(interval) }
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

        // ConfigStatusPresenter owns the ConfigInteractor lifecycle: its
        // stop() disarms the watch. Because the presenter was constructed
        // inside the bootstrap scope in start(), its `@Dependency` resolves the
        // same interactor instance here without a manual `withBootstrap` wrap.
        configStatusPresenter?.stop()
        defer { configStatusPresenter = nil }

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
