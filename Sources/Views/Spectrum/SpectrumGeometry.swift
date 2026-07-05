import Domain
import SwiftUI

// Pure spectrum bar geometry (#23). Every function here is a pure mapping of
// (size, heights, style) → rects / points / alignment / paths, so it is
// unit-tested directly in `ViewsTests` without a live `GraphicsContext`. The
// Canvas drawing that consumes these lives in `SpectrumRendering.swift`; the
// SwiftUI view struct in `SpectrumView.swift`.

/// Endpoints of the strip-spanning gradient. `frequency` runs along the
/// track (edge-parallel) axis, `amplitude` along the growth axis from the
/// bars' base to their tips, so the high colors always land at the growing
/// edge whichever edge the strip anchors to.
func gradientEnds(
    for direction: SpectrumGradientDirection, size: CGSize, placement: SpectrumPlacement
) -> (CGPoint, CGPoint) {
    switch direction {
    case .frequency:
        return isHorizontal(placement)
            ? (CGPoint(x: size.width / 2, y: 0), CGPoint(x: size.width / 2, y: size.height))
            : (CGPoint(x: 0, y: size.height / 2), CGPoint(x: size.width, y: size.height / 2))
    case .amplitude:
        return amplitudeGradientEnds(placement: placement, size: size)
    case .level:
        return (.zero, .zero)
    }
}

/// Base → tip of the growth axis for the `amplitude` gradient, per edge.
func amplitudeGradientEnds(
    placement: SpectrumPlacement, size: CGSize
) -> (CGPoint, CGPoint) {
    switch placement {
    case .bottom, .underlay:
        return (CGPoint(x: size.width / 2, y: size.height), CGPoint(x: size.width / 2, y: 0))
    case .top:
        return (CGPoint(x: size.width / 2, y: 0), CGPoint(x: size.width / 2, y: size.height))
    case .left:
        return (CGPoint(x: 0, y: size.height / 2), CGPoint(x: size.width, y: size.height / 2))
    case .right:
        return (CGPoint(x: size.width, y: size.height / 2), CGPoint(x: 0, y: size.height / 2))
    }
}

/// Growth-axis depth of the strip resolved from the placement's `SpectrumStyle`
/// fields (a thin adapter over `spectrumBarStripDepth`).
func barStripDepth(in available: CGSize, style: SpectrumStyle) -> CGFloat {
    spectrumBarStripDepth(
        in: available, placement: style.placement, heightRatio: style.heightRatio,
        minHeight: style.minHeight, maxHeight: style.maxHeight)
}

/// Length of the track the bars distribute along — width for vertical
/// placements, height for the horizontal ones — reported to the Presenter
/// so it can derive the bar count.
func trackExtent(of size: CGSize, placement: SpectrumPlacement) -> Double {
    isHorizontal(placement) ? size.height : size.width
}

/// SwiftUI alignment that pins the strip against its anchoring edge.
func spectrumAlignment(for placement: SpectrumPlacement) -> Alignment {
    switch placement {
    case .bottom, .underlay: .bottom
    case .top: .top
    case .left: .leading
    case .right: .trailing
    }
}

/// Horizontal placements rotate the bars into columns growing sideways; the
/// vertical ones grow the bars up or down.
func isHorizontal(_ placement: SpectrumPlacement) -> Bool {
    switch placement {
    case .left, .right: true
    case .bottom, .top, .underlay: false
    }
}

/// Growth-axis extent of the bar strip: `heightRatio` of the axis (the overlay
/// height for vertical placements, the width for horizontal), then clamped
/// into the optional `[minHeight, maxHeight]` point range (CSS
/// `min-height`/`max-height` semantics — min wins on conflict) and never
/// beyond the axis itself. `underlay` fills the full height and ignores the
/// clamp (it's a backdrop). The clamp keeps a ratio-based length sane across
/// very different displays — e.g. capping a horizontal placement on an
/// ultrawide, where a pure ratio would stretch it across the screen.
func spectrumBarStripDepth(
    in available: CGSize, placement: SpectrumPlacement, heightRatio: Double,
    minHeight: Double?, maxHeight: Double?
) -> CGFloat {
    guard placement != .underlay else { return available.height }
    let axis = isHorizontal(placement) ? available.width : available.height
    let preferred = axis * CGFloat(min(max(heightRatio, 0), 1))
    let capped = maxHeight.map { min(preferred, CGFloat($0)) } ?? preferred
    let floored = minHeight.map { max(capped, CGFloat($0)) } ?? capped
    return min(max(floored, 0), axis)
}

/// One visible bar: its rounded rect and its 0…1 height, used to pick the
/// per-bar color in the `level` gradient direction.
struct SpectrumBar: Equatable {
    let rect: CGRect
    let cornerRadius: CGFloat
    let level: Float
}

/// The visible bars of the current frame — those long enough to draw — laid
/// out at a fixed `barWidth` thickness and `barSpacing` gap (cava style) and
/// centered along the track. Each bar grows along the axis perpendicular to
/// its anchoring edge: up/down for `bottom`/`top`, left↔right for the
/// horizontal placements. Bars below half a point are dropped so the path
/// carries no invisible slivers.
func spectrumBarRects(
    in size: CGSize, heights: [Float], barWidth: Double, barSpacing: Double,
    placement: SpectrumPlacement, cornerRadius: Double? = nil
) -> [SpectrumBar] {
    guard !heights.isEmpty, size.width > 0, size.height > 0 else { return [] }
    let thickness = CGFloat(max(barWidth, 0.5))
    let spacing = CGFloat(max(barSpacing, 0))
    let count = heights.count
    // Track = the edge-parallel axis the bars are distributed along; growth =
    // the perpendicular axis a bar extends along with its level.
    let horizontal = isHorizontal(placement)
    let trackLength = horizontal ? size.height : size.width
    let growthExtent = horizontal ? size.width : size.height
    let rowLength = CGFloat(count) * thickness + CGFloat(max(count - 1, 0)) * spacing
    let start = max((trackLength - rowLength) / 2, 0)
    // An explicit radius is clamped to the bar half-thickness (a rounded rect
    // can't curve more than that); `nil` derives the cava-style default.
    let barCornerRadius =
        cornerRadius.map { min(max(CGFloat($0), 0), thickness / 2) }
        ?? autoCornerRadius(thickness: thickness)
    return heights.enumerated().compactMap { bar in
        let level = min(max(bar.element, 0), 1)
        let growth = growthExtent * CGFloat(level)
        guard growth > 0.5 else { return nil }
        let track = start + CGFloat(bar.offset) * (thickness + spacing)
        let rect = barRect(
            placement: placement, track: track, thickness: thickness, growth: growth, in: size)
        return SpectrumBar(rect: rect, cornerRadius: barCornerRadius, level: level)
    }
}

/// The cava-style default corner radius for a bar of the given thickness:
/// a quarter of the thickness, capped at 3 pt, so thin bars stay legibly
/// rounded and thick ones don't turn into lozenges.
func autoCornerRadius(thickness: CGFloat) -> CGFloat {
    min(thickness / 4, 3)
}

/// One bar's rect, anchored to its placement's edge and grown inward by
/// `growth` from a track offset.
private func barRect(
    placement: SpectrumPlacement, track: CGFloat, thickness: CGFloat, growth: CGFloat,
    in size: CGSize
) -> CGRect {
    switch placement {
    case .bottom, .underlay:
        return CGRect(x: track, y: size.height - growth, width: thickness, height: growth)
    case .top:
        return CGRect(x: track, y: 0, width: thickness, height: growth)
    case .left:
        return CGRect(x: 0, y: track, width: growth, height: thickness)
    case .right:
        return CGRect(x: size.width - growth, y: track, width: growth, height: thickness)
    }
}

/// One path over the given bars, so a single gradient fill spans them all
/// instead of restarting per bar.
func barsPath(_ bars: [SpectrumBar]) -> Path {
    bars.reduce(into: Path()) { path, bar in
        path.addRoundedRect(
            in: bar.rect, cornerSize: CGSize(width: bar.cornerRadius, height: bar.cornerRadius))
    }
}
