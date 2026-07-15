import Foundation
import Presenters
import SwiftUI

/// Graphical error indicator for config hot-reload failures (#41). When the
/// daemon's file watcher picks up a config edit that fails to parse, the
/// previous (still valid) style stays in effect — but a daemon user watching
/// the overlay has no terminal to read a log line from, so the failure must
/// be conveyed visually. Reuses the loading sphere's visual language (a
/// Canvas-drawn geodesic wireframe) but recolored amber and deliberately
/// "destabilized" — some struts missing, others buckled outward — so it
/// reads as an error at a glance and is never mistaken for the gold loading
/// sphere. Small and corner-anchored so it never competes with the header or
/// lyrics for attention.
public struct ConfigStatusOverlay: View {
    @ObservedObject var presenter: ConfigStatusPresenter

    public init(presenter: ConfigStatusPresenter) {
        self.presenter = presenter
    }

    public var body: some View {
        // Same zero-idle-cost shape as `WallpaperLoadingOverlay` (#252): the
        // animated `TimelineView`/Canvas exists only while a config failure
        // is active, so the common (valid config) case has no per-frame
        // redraw cost anywhere in this view.
        ZStack(alignment: .bottomTrailing) {
            if presenter.invalidConfig != nil {
                ConfigStatusContent()
                    .accessibilityIdentifier("config-status-overlay")
                    .allowsHitTesting(false)
                    .padding(24)
                    .transition(.scale(scale: 0.82).combined(with: .opacity))
            }
        }
        // Without this, the ZStack only sizes to its (small) badge content,
        // so `.bottomTrailing` above only aligns the badge within its own
        // intrinsic box instead of the overlay window — the badge renders
        // centered inside `OverlayContentView`'s outer ZStack instead of in
        // the intended bottom-right corner. Stretching to fill makes the
        // alignment apply across the full overlay.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .animation(.easeInOut(duration: 0.4), value: presenter.invalidConfig != nil)
    }
}

/// The indicator's on-screen content: the destabilized amber sphere with a
/// small caption beneath it. Composed once and reused by both the live
/// overlay and the SwiftUI preview.
private struct ConfigStatusContent: View {
    var body: some View {
        VStack(spacing: 12) {
            DestabilizedGeodesicIndicator()
            ConfigStatusCaption()
        }
    }
}

/// Small caption under the sphere naming what happened. Kept terse and low
/// key — this is a corner notice, not a modal — but still legible over both
/// a bright and a dark wallpaper via the same dark-halo shadow strategy used
/// by the loading caption.
private struct ConfigStatusCaption: View {
    var body: some View {
        Text("config invalid · kept previous style")
            .font(.system(size: 10, weight: .medium))
            .tracking(1.5)
            .foregroundStyle(configStatusAmberBright.opacity(0.9))
            .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
    }
}

// MARK: - Destabilized geodesic indicator

/// A "broken" sibling of `GeodesicLoadingIndicator`: the same Goldberg-sphere
/// wireframe (`GeodesicGeometry.edges`, shared and rotation-independent), but
/// re-colored amber and rendered with a deterministic strut-failure mask so
/// it never reads as "still loading" — every 7th edge dropped, surviving
/// edges radially jittered by a deterministic per-index function (never
/// `Int.random`/`arc4random`), so the shape is identical on every frame and
/// every launch. The projection/jitter math lives in `ConfigStatusGeometry`
/// (unit-tested); the `GraphicsContext` stroking lives in
/// `ConfigStatusRenderer`. This view only wires the `TimelineView`/`Canvas`
/// scaffold and delegates drawing — mirrors the `SpectrumView` split (#23).
@MainActor
private struct DestabilizedGeodesicIndicator: View {
    private let renderer = ConfigStatusRenderer()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                renderer.draw(&context, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .frame(width: configStatusDiameter, height: configStatusDiameter)
    }
}

private let configStatusDiameter: CGFloat = 120  // smaller than the loading sphere (196) — a corner badge, not a centerpiece

#if DEBUG
    #Preview("Config Status") {
        // Side-by-side bright / dark stand-in wallpapers to judge that the
        // destabilized sphere reads clearly — and distinctly from the gold
        // loading sphere — against either extreme.
        HStack(spacing: 0) {
            ZStack {
                LinearGradient(
                    colors: [.white, Color(red: 0.95, green: 0.92, blue: 0.80)],
                    startPoint: .top, endPoint: .bottom)
                ConfigStatusContent()
            }
            ZStack {
                LinearGradient(
                    colors: [.black, Color(red: 0.10, green: 0.10, blue: 0.16)],
                    startPoint: .top, endPoint: .bottom)
                ConfigStatusContent()
            }
        }
        .frame(width: 420, height: 260)
        .ignoresSafeArea()
    }
#endif
