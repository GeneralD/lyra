import SwiftUI

/// Canvas drawing for the destabilized geodesic sphere (#41 config-invalid
/// indicator). Owns the irreducible `GraphicsContext` side of the render —
/// `context.stroke` — so it is `@MainActor` and lives apart from both the
/// pure geometry (`ConfigStatusGeometry`, unit-tested) and the SwiftUI view
/// struct (`ConfigStatusOverlay`, declaration only). Mirrors the
/// `SpectrumRenderer` split (#23): thin by design and not unit-tested, since
/// every value it draws already came from the tested geometry.
@MainActor
struct ConfigStatusRenderer {
    private let geometry = ConfigStatusGeometry()

    init() {}

    /// Paints one frame of the destabilized sphere: every surviving,
    /// depth-sorted edge from `ConfigStatusGeometry`, far-to-near so the near
    /// panels sit on top of the far ones (cheap painter's-algorithm depth) —
    /// same technique as the gold `GeodesicLoadingIndicator`.
    func draw(_ context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        for edge in geometry.edges(in: size, time: time) {
            drawEdge(&context, p: edge.start, q: edge.end)
        }
    }

    /// A single strut, drawn with the same dark-halo-then-color technique as
    /// the loading indicator so it stays legible over both a bright and a
    /// dark wallpaper — but amber instead of gold.
    private func drawEdge(
        _ context: inout GraphicsContext,
        p: ConfigStatusProjectedVertex, q: ConfigStatusProjectedVertex
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

private let configStatusMinLineWidth: CGFloat = 0.5
private let configStatusLineWidthRange: CGFloat = 1.1
private let configStatusHaloPadding: CGFloat = 1.1

/// Two amber tones mirroring `GeodesicGold`'s bright/mid split, so the error
/// indicator shares the same depth-shading technique while staying visually
/// distinct (amber vs. gold) from the loading sphere at a glance. Not
/// `private` — `ConfigStatusCaption` (in `ConfigStatusOverlay.swift`) reuses
/// `configStatusAmberBright` for its text color.
let configStatusAmberBright = Color(red: 1.000, green: 0.700, blue: 0.300)
let configStatusAmberMid = Color(red: 0.850, green: 0.520, blue: 0.180)
