import Entity
import Foundation
import SwiftUI
import Testing

@testable import Views

@Suite("spectrumBarRects")
struct SpectrumBarRectsTests {
    private let size = CGSize(width: 100, height: 200)

    @Test("one bar per height, sized to its level")
    func barPerHeight() {
        let bars = spectrumBarRects(
            in: size, heights: [1, 0.5], barWidth: 10, barSpacing: 2, placement: .bottom)
        #expect(bars.count == 2)
        #expect(bars[0].level == 1)
        #expect(abs(bars[0].rect.height - 200) < 0.01)
        #expect(abs(bars[1].rect.height - 100) < 0.01)
    }

    @Test("bars keep the fixed width and gap regardless of count")
    func fixedWidthAndSpacing() {
        let bars = spectrumBarRects(
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
        let bars = spectrumBarRects(
            in: size, heights: [1, 1], barWidth: 10, barSpacing: 2, placement: .bottom)
        #expect(abs(bars[0].rect.minX - 39) < 0.01)
    }

    @Test("bars below half a point are dropped")
    func dropsInvisibleBars() {
        // 0.001 * 200 = 0.2 pt < 0.5 → dropped; the tall one stays.
        let bars = spectrumBarRects(
            in: size, heights: [0.001, 1], barWidth: 10, barSpacing: 2, placement: .bottom)
        #expect(bars.count == 1)
        #expect(bars[0].level == 1)
    }

    @Test("bottom placement grows bars up from the bottom edge")
    func bottomAnchors() {
        let bars = spectrumBarRects(
            in: size, heights: [0.5], barWidth: 10, barSpacing: 2, placement: .bottom)
        #expect(abs((bars[0].rect.maxY) - 200) < 0.01)
    }

    @Test("top placement grows bars down from the top edge")
    func topAnchors() {
        let bars = spectrumBarRects(
            in: size, heights: [0.5], barWidth: 10, barSpacing: 2, placement: .top)
        #expect(abs(bars[0].rect.minY) < 0.01)
    }

    @Test("left placement grows horizontal bars rightward from the left edge")
    func leftAnchors() {
        let bars = spectrumBarRects(
            in: size, heights: [0.5], barWidth: 10, barSpacing: 2, placement: .left)
        // The bar rotates: thickness becomes its height, the level drives width.
        #expect(abs(bars[0].rect.minX) < 0.01)
        #expect(abs(bars[0].rect.width - 50) < 0.01)  // 0.5 * width(100)
        #expect(abs(bars[0].rect.height - 10) < 0.01)  // barWidth = thickness
    }

    @Test("right placement grows horizontal bars leftward from the right edge")
    func rightAnchors() {
        let bars = spectrumBarRects(
            in: size, heights: [0.5], barWidth: 10, barSpacing: 2, placement: .right)
        #expect(abs(bars[0].rect.maxX - 100) < 0.01)  // flush to the right edge
        #expect(abs(bars[0].rect.width - 50) < 0.01)
    }

    @Test("horizontal placements distribute bars down the height, centered")
    func horizontalTrackIsVertical() {
        // Two 10 pt-thick bars + one 2 pt gap = 22 pt column on the 200 pt
        // height → (200 - 22) / 2 = 89 pt top margin, bars one slot (12) apart.
        let bars = spectrumBarRects(
            in: size, heights: [1, 1], barWidth: 10, barSpacing: 2, placement: .left)
        #expect(bars.count == 2)
        #expect(abs(bars[0].rect.minY - 89) < 0.01)
        #expect(abs(bars[1].rect.minY - bars[0].rect.minY - 12) < 0.01)
    }

    @Test("empty heights or zero size yields no bars")
    func emptyInputs() {
        #expect(
            spectrumBarRects(
                in: size, heights: [], barWidth: 10, barSpacing: 2, placement: .bottom
            ).isEmpty)
        #expect(
            spectrumBarRects(
                in: .zero, heights: [1], barWidth: 10, barSpacing: 2, placement: .bottom
            ).isEmpty)
    }
}

@Suite("spectrumBarStripDepth")
struct SpectrumBarStripDepthTests {
    private let size = CGSize(width: 100, height: 200)

    @Test("vertical placement takes the ratio of the height")
    func verticalUsesHeight() {
        let depth = spectrumBarStripDepth(
            in: size, placement: .bottom, heightRatio: 0.25, minHeight: nil, maxHeight: nil)
        #expect(abs(depth - 50) < 0.01)  // 0.25 * 200
    }

    @Test("horizontal placement takes the ratio of the width")
    func horizontalUsesWidth() {
        let depth = spectrumBarStripDepth(
            in: size, placement: .right, heightRatio: 0.25, minHeight: nil, maxHeight: nil)
        #expect(abs(depth - 25) < 0.01)  // 0.25 * 100
    }

    @Test("max_height caps the ratio-derived extent (ultrawide guard)")
    func maxCaps() {
        // A wide axis where a pure ratio would overshoot; the cap pins it.
        let wide = CGSize(width: 4000, height: 200)
        let depth = spectrumBarStripDepth(
            in: wide, placement: .right, heightRatio: 0.25, minHeight: nil, maxHeight: 300)
        #expect(abs(depth - 300) < 0.01)  // min(0.25 * 4000, 300)
    }

    @Test("min_height floors a tiny ratio")
    func minFloors() {
        let depth = spectrumBarStripDepth(
            in: size, placement: .bottom, heightRatio: 0.01, minHeight: 40, maxHeight: nil)
        #expect(abs(depth - 40) < 0.01)  // max(0.01 * 200, 40)
    }

    @Test("min wins over max on conflict (CSS semantics)")
    func minWinsOverMax() {
        let depth = spectrumBarStripDepth(
            in: size, placement: .bottom, heightRatio: 0.5, minHeight: 80, maxHeight: 40)
        #expect(abs(depth - 80) < 0.01)  // cap to 40, then floor to 80
    }

    @Test("the clamp never pushes past the axis length")
    func neverExceedsAxis() {
        let depth = spectrumBarStripDepth(
            in: size, placement: .bottom, heightRatio: 1, minHeight: 5000, maxHeight: nil)
        #expect(abs(depth - 200) < 0.01)  // floored to 5000, then capped at the 200 axis
    }

    @Test("underlay fills the full height and ignores the clamp")
    func underlayIgnoresClamp() {
        let depth = spectrumBarStripDepth(
            in: size, placement: .underlay, heightRatio: 0.25, minHeight: 10, maxHeight: 30)
        #expect(abs(depth - 200) < 0.01)
    }
}

@Suite("gradientEnds")
struct SpectrumGradientEndsTests {
    private let size = CGSize(width: 100, height: 200)

    @Test("frequency runs along the track (edge-parallel) axis for vertical placements")
    func frequencyVertical() {
        let (start, end) = gradientEnds(for: .frequency, size: size, placement: .bottom)
        #expect(start == CGPoint(x: 0, y: 100))
        #expect(end == CGPoint(x: 100, y: 100))
    }

    @Test("frequency runs across the track for horizontal placements")
    func frequencyHorizontal() {
        let (start, end) = gradientEnds(for: .frequency, size: size, placement: .right)
        #expect(start == CGPoint(x: 50, y: 0))
        #expect(end == CGPoint(x: 50, y: 200))
    }

    @Test("level collapses to a zero-length gradient (unused for per-bar fills)")
    func levelIsZero() {
        let (start, end) = gradientEnds(for: .level, size: size, placement: .bottom)
        #expect(start == .zero)
        #expect(end == .zero)
    }

    @Test("amplitude delegates to the per-edge growth axis")
    func amplitudeDelegates() {
        #expect(
            gradientEnds(for: .amplitude, size: size, placement: .bottom)
                == amplitudeGradientEnds(placement: .bottom, size: size))
    }

    @Test("amplitude runs base→tip of the growth axis, per anchoring edge")
    func amplitudePerEdge() {
        #expect(
            amplitudeGradientEnds(placement: .bottom, size: size)
                == (CGPoint(x: 50, y: 200), CGPoint(x: 50, y: 0)))
        #expect(
            amplitudeGradientEnds(placement: .top, size: size)
                == (CGPoint(x: 50, y: 0), CGPoint(x: 50, y: 200)))
        #expect(
            amplitudeGradientEnds(placement: .left, size: size)
                == (CGPoint(x: 0, y: 100), CGPoint(x: 100, y: 100)))
        #expect(
            amplitudeGradientEnds(placement: .right, size: size)
                == (CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100)))
    }
}

@Suite("spectrum geometry helpers")
struct SpectrumGeometryHelpersTests {
    private let size = CGSize(width: 100, height: 200)

    @Test("trackExtent is the width for vertical placements, the height for horizontal")
    func trackExtentAxis() {
        #expect(trackExtent(of: size, placement: .bottom) == 100)
        #expect(trackExtent(of: size, placement: .top) == 100)
        #expect(trackExtent(of: size, placement: .underlay) == 100)
        #expect(trackExtent(of: size, placement: .left) == 200)
        #expect(trackExtent(of: size, placement: .right) == 200)
    }

    @Test("spectrumAlignment pins the strip against its anchoring edge")
    func alignmentPerEdge() {
        #expect(spectrumAlignment(for: .bottom) == .bottom)
        #expect(spectrumAlignment(for: .underlay) == .bottom)
        #expect(spectrumAlignment(for: .top) == .top)
        #expect(spectrumAlignment(for: .left) == .leading)
        #expect(spectrumAlignment(for: .right) == .trailing)
    }

    @Test("barStripDepth adapts the SpectrumStyle fields onto spectrumBarStripDepth")
    func barStripDepthAdapter() {
        // Defaults: placement .bottom, heightRatio 0.25, no min/max clamp.
        let style = SpectrumStyle()
        #expect(abs(barStripDepth(in: size, style: style) - 50) < 0.01)  // 0.25 * 200
    }
}
