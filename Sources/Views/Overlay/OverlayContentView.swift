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

/// A point on the unit sphere. Internal (not `private`) so the pure geometry in
/// `GeodesicGeometry` can be unit-tested via `@testable import Views`.
struct Vertex3D {
    let x, y, z: Double
}

/// Wireframe edges of a gold geodesic sphere. The geometry is the DUAL of a
/// once-subdivided icosphere: start from an icosahedron, subdivide each of its
/// 20 triangles into 4 (an 80-triangle "icosphere"), then connect the centroid
/// of every triangle to its edge-neighbours. The result is a Goldberg
/// polyhedron — 12 pentagons + 30 hexagons, a soccer ball with a few extra
/// faces. Geometry is independent of rotation, so it is built once and reused
/// for every frame. Internal (not `private`) so the edge generation can be
/// unit-tested via `@testable import Views`.
enum GeodesicGeometry {
    static let edges: [(Vertex3D, Vertex3D)] = buildEdges()

    private static func normalized(_ v: Vertex3D) -> Vertex3D {
        let length = (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot()
        return Vertex3D(x: v.x / length, y: v.y / length, z: v.z / length)
    }

    /// Order-independent key for an undirected vertex pair.
    private static func key(_ a: Int, _ b: Int) -> Int64 {
        a < b ? (Int64(a) << 32) | Int64(b) : (Int64(b) << 32) | Int64(a)
    }

    private static func buildEdges() -> [(Vertex3D, Vertex3D)] {
        let t = (1 + 5.0.squareRoot()) / 2  // golden ratio
        var verts: [Vertex3D] = [
            Vertex3D(x: -1, y: t, z: 0), Vertex3D(x: 1, y: t, z: 0),
            Vertex3D(x: -1, y: -t, z: 0), Vertex3D(x: 1, y: -t, z: 0),
            Vertex3D(x: 0, y: -1, z: t), Vertex3D(x: 0, y: 1, z: t),
            Vertex3D(x: 0, y: -1, z: -t), Vertex3D(x: 0, y: 1, z: -t),
            Vertex3D(x: t, y: 0, z: -1), Vertex3D(x: t, y: 0, z: 1),
            Vertex3D(x: -t, y: 0, z: -1), Vertex3D(x: -t, y: 0, z: 1),
        ].map(normalized)
        let base: [[Int]] = [
            [0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
            [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
            [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
            [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
        ]
        var cache: [Int64: Int] = [:]
        func mid(_ a: Int, _ b: Int) -> Int {
            let k = key(a, b)
            if let cached = cache[k] { return cached }
            let va = verts[a]
            let vb = verts[b]
            verts.append(
                normalized(
                    Vertex3D(x: (va.x + vb.x) / 2, y: (va.y + vb.y) / 2, z: (va.z + vb.z) / 2)))
            cache[k] = verts.count - 1
            return verts.count - 1
        }
        let faces = base.flatMap { f -> [[Int]] in
            let ab = mid(f[0], f[1])
            let bc = mid(f[1], f[2])
            let ca = mid(f[2], f[0])
            return [[f[0], ab, ca], [f[1], bc, ab], [f[2], ca, bc], [ab, bc, ca]]
        }
        let centroids = faces.map { f -> Vertex3D in
            let a = verts[f[0]]
            let b = verts[f[1]]
            let c = verts[f[2]]
            return normalized(
                Vertex3D(x: (a.x + b.x + c.x) / 3, y: (a.y + b.y + c.y) / 3, z: (a.z + b.z + c.z) / 3))
        }
        var edgeFaces: [Int64: [Int]] = [:]
        for (index, f) in faces.enumerated() {
            for (u, v) in [(f[0], f[1]), (f[1], f[2]), (f[2], f[0])] {
                edgeFaces[key(u, v), default: []].append(index)
            }
        }
        return edgeFaces.values.compactMap {
            $0.count == 2 ? (centroids[$0[0]], centroids[$0[1]]) : nil
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
