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
/// it never reads as "still loading". Two deviations from the gold sphere,
/// both a pure function of an edge's index — never `Int.random`/`arc4random`
/// — so the shape is identical on every frame and every launch:
///
/// - **Missing struts**: every 7th edge (by index into `GeodesicGeometry.edges`)
///   is dropped entirely, leaving visible gaps in the wireframe.
/// - **Buckled struts**: surviving edges get a small per-index radial jitter
///   (`sin(index * step)`), so the sphere reads as caved-in rather than a
///   pristine rotating wireframe.
private struct DestabilizedGeodesicIndicator: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                draw(&context, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .frame(width: configStatusDiameter, height: configStatusDiameter)
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = size.width / 2 - configStatusRimInset
        let angle = time * configStatusSpinRate
        // Project every surviving edge, then paint back-to-front so the near
        // panels sit on top of the far ones (same cheap painter's-algorithm
        // depth as the loading indicator).
        let edges =
            GeodesicGeometry.edges
            .enumerated()
            .filter { !isBroken($0.offset) }
            .map {
                (
                    project($0.element.0, center: center, radius: radius, angle: angle, index: $0.offset),
                    project($0.element.1, center: center, radius: radius, angle: angle, index: $0.offset)
                )
            }
            .sorted { ($0.0.depth + $0.1.depth) < ($1.0.depth + $1.1.depth) }
        for (p, q) in edges {
            drawEdge(&context, p: p, q: q)
        }
    }

    /// Deterministic "missing strut" mask — no RNG, just an index modulus.
    private func isBroken(_ index: Int) -> Bool {
        index % 7 == 0
    }

    /// Deterministic per-edge outward/inward jitter (fraction of radius).
    /// The multiplier is irrational-ish relative to the modulus above so the
    /// jitter pattern doesn't visibly repeat in lockstep with the gaps.
    private func jitter(for index: Int) -> Double {
        configStatusJitterAmplitude * sin(Double(index) * 2.399963)
    }

    /// Spin around the vertical axis, apply a fixed tilt, displace radially
    /// by the deterministic per-edge jitter, then orthographically project.
    /// `depth` is the post-rotation z (front > 0).
    private func project(_ v: Vertex3D, center: CGPoint, radius: CGFloat, angle: Double, index: Int)
        -> (point: CGPoint, depth: Double)
    {
        let x1 = v.x * cos(angle) + v.z * sin(angle)
        let z1 = -v.x * sin(angle) + v.z * cos(angle)
        let y2 = v.y * cos(configStatusTilt) - z1 * sin(configStatusTilt)
        let z2 = v.y * sin(configStatusTilt) + z1 * cos(configStatusTilt)
        let jitteredRadius = radius * CGFloat(1 + jitter(for: index))
        return (
            CGPoint(
                x: center.x + jitteredRadius * CGFloat(x1),
                y: center.y - jitteredRadius * CGFloat(y2)),
            z2
        )
    }

    /// A single strut, drawn with the same dark-halo-then-color technique as
    /// the loading indicator so it stays legible over both a bright and a
    /// dark wallpaper — but amber instead of gold.
    private func drawEdge(
        _ context: inout GraphicsContext,
        p: (point: CGPoint, depth: Double), q: (point: CGPoint, depth: Double)
    ) {
        let depth = ((p.depth + q.depth) / 2 + 1) / 2  // 0 far … 1 near
        let alpha = 0.18 + depth * 0.82
        let lineWidth = configStatusMinLineWidth + CGFloat(depth) * configStatusLineWidthRange
        var path = Path()
        path.move(to: p.point)
        path.addLine(to: q.point)
        context.stroke(
            path, with: .color(.black.opacity(0.16 + depth * 0.24)),
            lineWidth: lineWidth + configStatusHaloPadding)
        context.stroke(
            path,
            with: .color(
                (depth > 0.5 ? configStatusAmberBright : configStatusAmberMid).opacity(alpha)),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }
}

private let configStatusDiameter: CGFloat = 120  // smaller than the loading sphere (196) — a corner badge, not a centerpiece
private let configStatusRimInset: CGFloat = 8
private let configStatusTilt: Double = 0.42  // radians — same fixed 3/4 view as the loading sphere
private let configStatusSpinRate: Double = 0.6  // slower than the loading spin (2.0) — steadier, reads as "settled", not "in progress"
private let configStatusMinLineWidth: CGFloat = 0.5
private let configStatusLineWidthRange: CGFloat = 1.1
private let configStatusHaloPadding: CGFloat = 1.1
private let configStatusJitterAmplitude: Double = 0.12  // fraction of radius a surviving strut endpoint is displaced

/// Two amber tones mirroring `GeodesicGold`'s bright/mid split, so the error
/// indicator shares the same depth-shading technique while staying visually
/// distinct (amber vs. gold) from the loading sphere at a glance.
private let configStatusAmberBright = Color(red: 1.000, green: 0.700, blue: 0.300)
private let configStatusAmberMid = Color(red: 0.850, green: 0.520, blue: 0.180)

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
