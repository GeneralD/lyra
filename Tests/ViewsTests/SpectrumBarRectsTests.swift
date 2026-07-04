import Foundation
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
