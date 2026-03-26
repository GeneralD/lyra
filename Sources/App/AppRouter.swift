import Dependencies
import Domain
import Foundation
import Presentation

/// Wireframe and coordination: creates Presenters, subscribes to Interactors,
/// dispatches updates, and manages the overlay window lifecycle.
@MainActor
public final class AppRouter {
    private let headerPresenter = HeaderPresenter()
    private let lyricsPresenter = LyricsPresenter()
    private let wallpaperPresenter = WallpaperPresenter()
    private let ripplePresenter = RipplePresenter()

    private var trackTask: Task<Void, Never>?
    private var overlay: OverlayWindow?

    @Dependency(\.trackInteractor) private var trackInteractor
    @Dependency(\.wallpaperInteractor) private var wallpaperInteractor

    public init() {}

    public func start() async {
        // Start Presenters
        headerPresenter.start()
        lyricsPresenter.start()
        ripplePresenter.start()

        // Resolve wallpaper
        await wallpaperPresenter.resolve()

        // Create overlay window
        let overlay = await OverlayWindow(
            headerPresenter: headerPresenter,
            lyricsPresenter: lyricsPresenter,
            ripplePresenter: ripplePresenter,
            wallpaperPresenter: wallpaperPresenter
        )
        self.overlay = overlay

        // Subscribe to TrackInteractor once, dispatch to both Presenters
        trackTask = Task { [weak self] in
            guard let self else { return }
            for await update in trackInteractor.observeTrack() {
                guard !Task.isCancelled else { break }
                headerPresenter.receive(update)
                lyricsPresenter.receive(update)
            }
        }
    }

    public func stop() {
        trackTask?.cancel()
        headerPresenter.stop()
        lyricsPresenter.stop()
        overlay?.close()
        overlay = nil
    }
}
