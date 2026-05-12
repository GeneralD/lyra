import Presenters
import SwiftUI

@MainActor
public struct OverlayContentView: View {
    let headerPresenter: HeaderPresenter
    let lyricsPresenter: LyricsPresenter
    let ripplePresenter: RipplePresenter
    @ObservedObject var wallpaperPresenter: WallpaperPresenter

    public init(
        headerPresenter: HeaderPresenter,
        lyricsPresenter: LyricsPresenter,
        ripplePresenter: RipplePresenter,
        wallpaperPresenter: WallpaperPresenter
    ) {
        self.headerPresenter = headerPresenter
        self.lyricsPresenter = lyricsPresenter
        self.ripplePresenter = ripplePresenter
        self.wallpaperPresenter = wallpaperPresenter
    }

    public var body: some View {
        ZStack {
            RippleView(presenter: ripplePresenter)
            VStack(alignment: .leading, spacing: 32) {
                HeaderView(presenter: headerPresenter)
                LyricsColumnView(presenter: lyricsPresenter)
            }
            .padding(48)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            WallpaperLoadingOverlay(presenter: wallpaperPresenter)
        }
        .accessibilityIdentifier("overlay-content")
    }
}

private struct WallpaperLoadingOverlay: View {
    @ObservedObject var presenter: WallpaperPresenter

    var body: some View {
        // Conditional inclusion (not `.opacity(0)`) so the spinner is removed
        // from the view tree when hidden. A `ProgressView` kept in the tree
        // drives a continuous CADisplayLink animation even while invisible,
        // which idle-burns CPU/GPU on every machine running lyra (#252).
        if presenter.showLoadingIndicator {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.large)
                .tint(.white)
                .accessibilityIdentifier("wallpaper-loading-indicator")
                .allowsHitTesting(false)
        }
    }
}

#if DEBUG
    #Preview("Overlay") {
        OverlayContentView(
            headerPresenter: HeaderPresenter(),
            lyricsPresenter: LyricsPresenter(),
            ripplePresenter: RipplePresenter(),
            wallpaperPresenter: WallpaperPresenter()
        )
        .frame(width: 800, height: 500)
        .background(.black)
    }
#endif
