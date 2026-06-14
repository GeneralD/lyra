import Foundation
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
        // The static `ZStack` host is always in the tree, but the animated
        // `GeodesicLoadingIndicator` (a `TimelineView` driving a per-frame Canvas)
        // is included only while loading. Conditional inclusion — not
        // `.opacity(0)` — is mandatory: an invisible-but-present timeline keeps
        // redrawing every frame and idle-burns CPU/GPU on every machine running
        // lyra (#252). The host is removed-when-hidden in spirit: nothing inside
        // animates until the indicator is inserted.
        ZStack {
            if presenter.showLoadingIndicator {
                LoadingIndicatorContent()
                    // Centered in the overlay, clear of the top-leading lyrics
                    // (48pt inset), so it never fights the lyric column.
                    .accessibilityIdentifier("wallpaper-loading-indicator")
                    .allowsHitTesting(false)
                    .transition(.scale(scale: 0.82).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.4), value: presenter.showLoadingIndicator)
    }
}

/// The loading indicator's on-screen content: the rotating gold sphere with a
/// subtle caption beneath it naming what the wait is for. Composed once and
/// reused by both the live overlay and the SwiftUI preview.
private struct LoadingIndicatorContent: View {
    var body: some View {
        VStack(spacing: 20) {  // breathing room between the sphere and its caption
            GeodesicLoadingIndicator()
            LoadingCaption()
        }
    }
}

/// Subtle caption under the sphere telling the user what the wait is for. Thin,
/// letter-spaced gold with a soft dark shadow so it stays legible over BOTH a
/// bright and a dark wallpaper (mirrors the sphere's dark-halo strategy) without
/// pulling focus from the rotating wireframe.
private struct LoadingCaption: View {
    var body: some View {
        Text("Downloading wallpaper")
            .font(.system(size: 12, weight: .medium))
            .tracking(2.5)
            .foregroundStyle(GeodesicGold.bright.opacity(0.9))
            .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
    }
}

// MARK: - Geodesic loading indicator

/// Indeterminate loading indicator in Lyra's visual language: a gold geodesic
/// sphere — a Goldberg polyhedron (12 pentagons + 30 hexagons, a soccer ball
/// with a few extra faces) — slowly rotating in 3D. Rendered on a `Canvas`
/// driven by `TimelineView(.animation)` so the motion is GPU-driven rather than
/// timer-driven, matching `RippleView`. The whole view exists only while the
/// download is in flight (see `WallpaperLoadingOverlay`), so there is no idle
/// timeline to pause here. The wireframe geometry is rotation-independent and
/// built a single time (`GeodesicGeometry.edges`); only the projection changes
/// per frame.
private struct GeodesicLoadingIndicator: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                draw(&context, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .frame(width: GeodesicMetrics.diameter, height: GeodesicMetrics.diameter)
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = size.width / 2 - GeodesicMetrics.rimInset
        let angle = time * GeodesicMetrics.spinRate
        // Project every edge, then paint back-to-front so the near panels of the
        // sphere sit on top of the far ones (cheap painter's-algorithm depth).
        let edges =
            GeodesicGeometry.edges
            .map {
                (
                    project($0.0, center: center, radius: radius, angle: angle),
                    project($0.1, center: center, radius: radius, angle: angle)
                )
            }
            .sorted { ($0.0.depth + $0.1.depth) < ($1.0.depth + $1.1.depth) }
        for (p, q) in edges {
            drawEdge(&context, p: p, q: q)
        }
    }

    /// Spin around the vertical axis, apply a fixed tilt for a 3/4 view, and
    /// orthographically project. `depth` is the post-rotation z (front > 0).
    private func project(_ v: Vertex3D, center: CGPoint, radius: CGFloat, angle: Double)
        -> (point: CGPoint, depth: Double)
    {
        let x1 = v.x * cos(angle) + v.z * sin(angle)
        let z1 = -v.x * sin(angle) + v.z * cos(angle)
        let y2 = v.y * cos(GeodesicMetrics.tilt) - z1 * sin(GeodesicMetrics.tilt)
        let z2 = v.y * sin(GeodesicMetrics.tilt) + z1 * cos(GeodesicMetrics.tilt)
        return (
            CGPoint(x: center.x + radius * CGFloat(x1), y: center.y - radius * CGFloat(y2)), z2
        )
    }

    /// A single strut. Each is drawn twice — a soft dark halo underneath and the
    /// gold line on top — so it stays legible over BOTH a bright and a dark
    /// wallpaper without any backing disc (#248). Far struts are thinner and
    /// fainter, near struts thicker and brighter, giving the wireframe depth.
    private func drawEdge(
        _ context: inout GraphicsContext,
        p: (point: CGPoint, depth: Double), q: (point: CGPoint, depth: Double)
    ) {
        let depth = ((p.depth + q.depth) / 2 + 1) / 2  // 0 far … 1 near
        let alpha = 0.18 + depth * 0.82
        let lineWidth = GeodesicMetrics.minLineWidth + CGFloat(depth) * GeodesicMetrics.lineWidthRange
        var path = Path()
        path.move(to: p.point)
        path.addLine(to: q.point)
        context.stroke(
            path, with: .color(.black.opacity(0.16 + depth * 0.24)),
            lineWidth: lineWidth + GeodesicMetrics.haloPadding)
        context.stroke(
            path,
            with: .color((depth > 0.5 ? GeodesicGold.bright : GeodesicGold.mid).opacity(alpha)),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }
}

private enum GeodesicMetrics {
    static let diameter: CGFloat = 196
    static let rimInset: CGFloat = 10
    static let tilt: Double = 0.42  // radians — fixed 3/4 view
    static let spinRate: Double = 2.0  // radians/sec (≈3.1 s per turn)
    static let minLineWidth: CGFloat = 0.5
    static let lineWidthRange: CGFloat = 1.1
    static let haloPadding: CGFloat = 1.1
}

/// Two solid gold tones mirrored from the lyric-highlight gradient
/// (`#B8942D → #EDCF73 → #FFEB99 → #CCA64D → #A68038`) so the indicator shares
/// Lyra's signature gold identity. `bright` is used for near struts, `mid` for
/// far ones.
private enum GeodesicGold {
    static let bright = Color(red: 1.000, green: 0.922, blue: 0.600)
    static let mid = Color(red: 0.929, green: 0.812, blue: 0.451)
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

    #Preview("Loading Indicator") {
        // Side-by-side bright / dark stand-in wallpapers to judge that the
        // indicator reads clearly against either extreme.
        HStack(spacing: 0) {
            ZStack {
                LinearGradient(
                    colors: [.white, Color(red: 0.95, green: 0.92, blue: 0.80)],
                    startPoint: .top, endPoint: .bottom)
                LoadingIndicatorContent()
            }
            ZStack {
                LinearGradient(
                    colors: [.black, Color(red: 0.10, green: 0.10, blue: 0.16)],
                    startPoint: .top, endPoint: .bottom)
                LoadingIndicatorContent()
            }
        }
        .frame(width: 520, height: 320)
        .ignoresSafeArea()
    }
#endif
