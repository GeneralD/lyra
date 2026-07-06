import Entity
import Foundation
import SwiftUI
import Testing

@testable import Views

@Suite("SpectrumGeometry.barRects")
struct SpectrumBarRectsTests {
    private let geometry = SpectrumGeometry()
    private let size = CGSize(width: 100, height: 200)

    @Test("one bar per height, sized to its level")
    func barPerHeight() {
        let bars = geometry.barRects(
            in: size, heights: [1, 0.5], barWidth: 10, barSpacing: 2, placement: .bottom)
        #expect(bars.count == 2)
        #expect(bars[0].level == 1)
        #expect(abs(bars[0].rect.height - 200) < 0.01)
        #expect(abs(bars[1].rect.height - 100) < 0.01)
    }

    @Test("bars keep the fixed width and gap regardless of count")
    func fixedWidthAndSpacing() {
        let bars = geometry.barRects(
            in: size, heights: [1, 1], barWidth: 10, barSpacing: 2, placement: .bottom)
        #expect(bars.count == 2)
        #expect(abs(bars[0].rect.width - 10) < 0.01)
        // Neighboring bars sit one slot (width + spacing) apart.
        #expect(abs(bars[1].rect.minX - bars[0].rect.minX - 12) < 0.01)
    }

    @Test("the row is centered in the available width")
    func rowIsCentered() {
        // Two 10 pt bars + one 2 pt gap = 22 pt row in a 100 pt width →
        // (100 - 22) / 2 = 39 pt left margin.
        let bars = geometry.barRects(
            in: size, heights: [1, 1], barWidth: 10, barSpacing: 2, placement: .bottom)
        #expect(abs(bars[0].rect.minX - 39) < 0.01)
    }

    @Test("bars below half a point are dropped")
    func dropsInvisibleBars() {
        // 0.001 * 200 = 0.2 pt < 0.5 → dropped; the tall one stays.
        let bars = geometry.barRects(
            in: size, heights: [0.001, 1], barWidth: 10, barSpacing: 2, placement: .bottom)
        #expect(bars.count == 1)
        #expect(bars[0].level == 1)
    }

    @Test("bottom placement grows bars up from the bottom edge")
    func bottomAnchors() {
        let bars = geometry.barRects(
            in: size, heights: [0.5], barWidth: 10, barSpacing: 2, placement: .bottom)
        #expect(abs((bars[0].rect.maxY) - 200) < 0.01)
    }

    @Test("top placement grows bars down from the top edge")
    func topAnchors() {
        let bars = geometry.barRects(
            in: size, heights: [0.5], barWidth: 10, barSpacing: 2, placement: .top)
        #expect(abs(bars[0].rect.minY) < 0.01)
    }

    @Test("left placement grows horizontal bars rightward from the left edge")
    func leftAnchors() {
        let bars = geometry.barRects(
            in: size, heights: [0.5], barWidth: 10, barSpacing: 2, placement: .left)
        // The bar rotates: thickness becomes its height, the level drives width.
        #expect(abs(bars[0].rect.minX) < 0.01)
        #expect(abs(bars[0].rect.width - 50) < 0.01)  // 0.5 * width(100)
        #expect(abs(bars[0].rect.height - 10) < 0.01)  // barWidth = thickness
    }

    @Test("right placement grows horizontal bars leftward from the right edge")
    func rightAnchors() {
        let bars = geometry.barRects(
            in: size, heights: [0.5], barWidth: 10, barSpacing: 2, placement: .right)
        #expect(abs(bars[0].rect.maxX - 100) < 0.01)  // flush to the right edge
        #expect(abs(bars[0].rect.width - 50) < 0.01)
    }

    @Test("horizontal placements distribute bars down the height, centered")
    func horizontalTrackIsVertical() {
        // Two 10 pt-thick bars + one 2 pt gap = 22 pt column on the 200 pt
        // height → (200 - 22) / 2 = 89 pt top margin, bars one slot (12) apart.
        let bars = geometry.barRects(
            in: size, heights: [1, 1], barWidth: 10, barSpacing: 2, placement: .left)
        #expect(bars.count == 2)
        #expect(abs(bars[0].rect.minY - 89) < 0.01)
        #expect(abs(bars[1].rect.minY - bars[0].rect.minY - 12) < 0.01)
    }

    @Test("empty heights or zero size yields no bars")
    func emptyInputs() {
        #expect(
            geometry.barRects(
                in: size, heights: [], barWidth: 10, barSpacing: 2, placement: .bottom
            ).isEmpty)
        #expect(
            geometry.barRects(
                in: .zero, heights: [1], barWidth: 10, barSpacing: 2, placement: .bottom
            ).isEmpty)
    }
}

@Suite("SpectrumGeometry.stripDepth")
struct SpectrumBarStripDepthTests {
    private let geometry = SpectrumGeometry()
    private let size = CGSize(width: 100, height: 200)

    @Test("vertical placement takes the ratio of the height")
    func verticalUsesHeight() {
        let depth = geometry.stripDepth(
            in: size, placement: .bottom, heightRatio: 0.25, minHeight: nil, maxHeight: nil)
        #expect(abs(depth - 50) < 0.01)  // 0.25 * 200
    }

    @Test("horizontal placement takes the ratio of the width")
    func horizontalUsesWidth() {
        let depth = geometry.stripDepth(
            in: size, placement: .right, heightRatio: 0.25, minHeight: nil, maxHeight: nil)
        #expect(abs(depth - 25) < 0.01)  // 0.25 * 100
    }

    @Test("max_height caps the ratio-derived extent (ultrawide guard)")
    func maxCaps() {
        // A wide axis where a pure ratio would overshoot; the cap pins it.
        let wide = CGSize(width: 4000, height: 200)
        let depth = geometry.stripDepth(
            in: wide, placement: .right, heightRatio: 0.25, minHeight: nil, maxHeight: 300)
        #expect(abs(depth - 300) < 0.01)  // min(0.25 * 4000, 300)
    }

    @Test("min_height floors a tiny ratio")
    func minFloors() {
        let depth = geometry.stripDepth(
            in: size, placement: .bottom, heightRatio: 0.01, minHeight: 40, maxHeight: nil)
        #expect(abs(depth - 40) < 0.01)  // max(0.01 * 200, 40)
    }

    @Test("min wins over max on conflict (CSS semantics)")
    func minWinsOverMax() {
        let depth = geometry.stripDepth(
            in: size, placement: .bottom, heightRatio: 0.5, minHeight: 80, maxHeight: 40)
        #expect(abs(depth - 80) < 0.01)  // cap to 40, then floor to 80
    }

    @Test("the clamp never pushes past the axis length")
    func neverExceedsAxis() {
        let depth = geometry.stripDepth(
            in: size, placement: .bottom, heightRatio: 1, minHeight: 5000, maxHeight: nil)
        #expect(abs(depth - 200) < 0.01)  // floored to 5000, then capped at the 200 axis
    }

    @Test("underlay fills the full height and ignores the clamp")
    func underlayIgnoresClamp() {
        let depth = geometry.stripDepth(
            in: size, placement: .underlay, heightRatio: 0.25, minHeight: 10, maxHeight: 30)
        #expect(abs(depth - 200) < 0.01)
    }
}

@Suite("SpectrumGeometry.gradientEnds")
struct SpectrumGradientEndsTests {
    private let geometry = SpectrumGeometry()
    private let size = CGSize(width: 100, height: 200)

    @Test("frequency runs along the track (edge-parallel) axis for vertical placements")
    func frequencyVertical() {
        let (start, end) = geometry.gradientEnds(for: .frequency, size: size, placement: .bottom)
        #expect(start == CGPoint(x: 0, y: 100))
        #expect(end == CGPoint(x: 100, y: 100))
    }

    @Test("frequency runs across the track for horizontal placements")
    func frequencyHorizontal() {
        let (start, end) = geometry.gradientEnds(for: .frequency, size: size, placement: .right)
        #expect(start == CGPoint(x: 50, y: 0))
        #expect(end == CGPoint(x: 50, y: 200))
    }

    @Test("level collapses to a zero-length gradient (unused for per-bar fills)")
    func levelIsZero() {
        let (start, end) = geometry.gradientEnds(for: .level, size: size, placement: .bottom)
        #expect(start == .zero)
        #expect(end == .zero)
    }

    @Test("amplitude delegates to the per-edge growth axis")
    func amplitudeDelegates() {
        #expect(
            geometry.gradientEnds(for: .amplitude, size: size, placement: .bottom)
                == geometry.amplitudeGradientEnds(placement: .bottom, size: size))
    }

    @Test("amplitude runs base→tip of the growth axis, per anchoring edge")
    func amplitudePerEdge() {
        #expect(
            geometry.amplitudeGradientEnds(placement: .bottom, size: size)
                == (CGPoint(x: 50, y: 200), CGPoint(x: 50, y: 0)))
        #expect(
            geometry.amplitudeGradientEnds(placement: .top, size: size)
                == (CGPoint(x: 50, y: 0), CGPoint(x: 50, y: 200)))
        #expect(
            geometry.amplitudeGradientEnds(placement: .left, size: size)
                == (CGPoint(x: 0, y: 100), CGPoint(x: 100, y: 100)))
        #expect(
            geometry.amplitudeGradientEnds(placement: .right, size: size)
                == (CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100)))
    }
}

@Suite("SpectrumGeometry helpers")
struct SpectrumGeometryHelpersTests {
    private let geometry = SpectrumGeometry()
    private let size = CGSize(width: 100, height: 200)

    @Test("trackExtent is the width for vertical placements, the height for horizontal")
    func trackExtentAxis() {
        #expect(geometry.trackExtent(of: size, placement: .bottom) == 100)
        #expect(geometry.trackExtent(of: size, placement: .top) == 100)
        #expect(geometry.trackExtent(of: size, placement: .underlay) == 100)
        #expect(geometry.trackExtent(of: size, placement: .left) == 200)
        #expect(geometry.trackExtent(of: size, placement: .right) == 200)
    }

    @Test("alignment pins the strip against its anchoring edge")
    func alignmentPerEdge() {
        #expect(geometry.alignment(for: .bottom) == .bottom)
        #expect(geometry.alignment(for: .underlay) == .bottom)
        #expect(geometry.alignment(for: .top) == .top)
        #expect(geometry.alignment(for: .left) == .leading)
        #expect(geometry.alignment(for: .right) == .trailing)
    }

    @Test("stripDepth adapts the SpectrumStyle fields onto the core clamp")
    func stripDepthAdapter() {
        // Defaults: placement .bottom, heightRatio 0.25, no min/max clamp.
        let style = SpectrumStyle()
        #expect(abs(geometry.stripDepth(in: size, style: style) - 50) < 0.01)  // 0.25 * 200
    }
}

@Suite("SpectrumGeometry.autoCornerRadius")
struct AutoCornerRadiusTests {
    private let geometry = SpectrumGeometry()

    @Test("is a quarter of the thickness, capped at 3 pt")
    func quarterCappedAtThree() {
        #expect(geometry.autoCornerRadius(thickness: 4) == 1)  // 4/4 = 1
        #expect(geometry.autoCornerRadius(thickness: 8) == 2)  // 8/4 = 2
        #expect(geometry.autoCornerRadius(thickness: 20) == 3)  // 20/4 = 5, capped to 3
    }
}

@Suite("SpectrumGeometry.barRects corner radius")
struct SpectrumBarCornerRadiusTests {
    private let geometry = SpectrumGeometry()
    private let size = CGSize(width: 100, height: 200)

    private func firstBar(barWidth: Double, cornerRadius: Double?) -> SpectrumBar? {
        geometry.barRects(
            in: size, heights: [1], barWidth: barWidth, barSpacing: 2, placement: .bottom,
            cornerRadius: cornerRadius
        ).first
    }

    @Test("nil corner radius derives the cava-style default from the thickness")
    func nilDerivesAuto() {
        #expect(
            firstBar(barWidth: 8, cornerRadius: nil)?.cornerRadius
                == geometry.autoCornerRadius(thickness: 8))
    }

    @Test("an explicit corner radius overrides the default")
    func explicitOverrides() {
        #expect(firstBar(barWidth: 8, cornerRadius: 1)?.cornerRadius == 1)
    }

    @Test("zero corner radius yields square corners")
    func zeroIsSquare() {
        #expect(firstBar(barWidth: 8, cornerRadius: 0)?.cornerRadius == 0)
    }

    @Test("a corner radius past half the thickness is capped there")
    func cappedAtHalfThickness() {
        #expect(firstBar(barWidth: 6, cornerRadius: 100)?.cornerRadius == 3)  // thickness / 2
    }

    @Test("a negative corner radius is floored at 0")
    func negativeFloored() {
        #expect(firstBar(barWidth: 8, cornerRadius: -5)?.cornerRadius == 0)
    }
}

@Suite("SpectrumGeometry.barsPath")
struct SpectrumBarsPathTests {
    private let geometry = SpectrumGeometry()

    @Test("no bars yield an empty path")
    func emptyBars() {
        #expect(geometry.barsPath([]).isEmpty)
    }

    @Test("one bar yields a non-empty path bounded by its rect")
    func singleBar() {
        let rect = CGRect(x: 5, y: 10, width: 10, height: 20)
        let path = geometry.barsPath([SpectrumBar(rect: rect, cornerRadius: 0, level: 1)])
        #expect(!path.isEmpty)
        #expect(path.boundingRect == rect)
    }

    @Test("the path spans the union of every bar rect")
    func spansUnion() {
        let bars = [
            SpectrumBar(rect: CGRect(x: 0, y: 0, width: 10, height: 20), cornerRadius: 0, level: 1),
            SpectrumBar(rect: CGRect(x: 40, y: 10, width: 10, height: 30), cornerRadius: 0, level: 1),
        ]
        let bounds = geometry.barsPath(bars).boundingRect
        // Union of (0,0,10,20) and (40,10,10,30) → (0,0,50,40).
        #expect(abs(bounds.minX - 0) < 0.01)
        #expect(abs(bounds.minY - 0) < 0.01)
        #expect(abs(bounds.maxX - 50) < 0.01)
        #expect(abs(bounds.maxY - 40) < 0.01)
    }
}
