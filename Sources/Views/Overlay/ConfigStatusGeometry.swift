import Foundation
import SwiftUI

/// A single projected sphere vertex: its 2D screen point and its
/// post-rotation depth (front > 0), used both to position the strut endpoint
/// and to shade/size the stroke that uses it.
struct ConfigStatusProjectedVertex: Equatable {
    let point: CGPoint
    let depth: Double
}

/// One surviving strut of the destabilized sphere, its two endpoints already
/// projected — ready to be depth-sorted and stroked.
struct ConfigStatusEdge: Equatable {
    let start: ConfigStatusProjectedVertex
    let end: ConfigStatusProjectedVertex
}

/// Pure geometry for the "destabilized" geodesic sphere (#41 config-invalid
/// indicator): every method is a pure mapping of (size, time, index) →
/// projected points/edges, so it is unit-tested directly against a
/// `ConfigStatusGeometry` instance without a live `GraphicsContext`. The
/// Canvas drawing that consumes it lives in `ConfigStatusRenderer`; the
/// SwiftUI view struct in `ConfigStatusOverlay`. Mirrors the
/// `SpectrumGeometry`/`SpectrumRenderer` split (#23).
///
/// A "broken" sibling of the gold `GeodesicLoadingIndicator`'s wireframe
/// (`GeodesicGeometry.edges`, shared and rotation-independent): every 7th
/// edge is dropped, and surviving edges get a small deterministic per-index
/// radial jitter — never `Int.random`/`arc4random` — so the shape is
/// identical on every frame and every launch.
struct ConfigStatusGeometry {
    /// Every surviving, projected edge at `time`, sorted back-to-front
    /// (painter's algorithm) so the caller can stroke them in draw order.
    func edges(in size: CGSize, time: TimeInterval) -> [ConfigStatusEdge] {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = size.width / 2 - configStatusRimInset
        let angle = time * configStatusSpinRate
        return GeodesicGeometry.edges
            .enumerated()
            .filter { !isBroken($0.offset) }
            .map {
                ConfigStatusEdge(
                    start: project(
                        $0.element.0, center: center, radius: radius, angle: angle, index: $0.offset),
                    end: project(
                        $0.element.1, center: center, radius: radius, angle: angle, index: $0.offset)
                )
            }
            .sorted { ($0.start.depth + $0.end.depth) < ($1.start.depth + $1.end.depth) }
    }

    /// Deterministic "missing strut" mask — no RNG, just an index modulus.
    func isBroken(_ index: Int) -> Bool {
        index % 7 == 0
    }

    /// Deterministic per-edge outward/inward jitter (fraction of radius).
    /// The multiplier is irrational-ish relative to the modulus above so the
    /// jitter pattern doesn't visibly repeat in lockstep with the gaps.
    func jitter(for index: Int) -> Double {
        configStatusJitterAmplitude * sin(Double(index) * 2.399963)
    }

    /// Spin around the vertical axis, apply a fixed tilt, displace radially
    /// by the deterministic per-edge jitter, then orthographically project.
    /// `depth` is the post-rotation z (front > 0).
    func project(_ v: Vertex3D, center: CGPoint, radius: CGFloat, angle: Double, index: Int)
        -> ConfigStatusProjectedVertex
    {
        let x1 = v.x * cos(angle) + v.z * sin(angle)
        let z1 = -v.x * sin(angle) + v.z * cos(angle)
        let y2 = v.y * cos(configStatusTilt) - z1 * sin(configStatusTilt)
        let z2 = v.y * sin(configStatusTilt) + z1 * cos(configStatusTilt)
        let jitteredRadius = radius * CGFloat(1 + jitter(for: index))
        return ConfigStatusProjectedVertex(
            point: CGPoint(
                x: center.x + jitteredRadius * CGFloat(x1),
                y: center.y - jitteredRadius * CGFloat(y2)),
            depth: z2
        )
    }
}

// MARK: - Fixed visual-design constants

// Not user-configurable — this is Lyra's error-indicator identity, not a
// themeable style. `configStatusDiameter` lives in `ConfigStatusOverlay.swift`
// (the View's own `.frame` layout, not part of the projection math);
// `configStatusRimInset`/`Tilt`/`SpinRate`/`JitterAmplitude` parametrize the
// projection above.
let configStatusRimInset: CGFloat = 8
let configStatusTilt: Double = 0.42  // radians — same fixed 3/4 view as the loading sphere
let configStatusSpinRate: Double = 0.6  // slower than the loading spin (2.0) — steadier, reads as "settled", not "in progress"
let configStatusJitterAmplitude: Double = 0.12  // fraction of radius a surviving strut endpoint is displaced
