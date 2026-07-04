import Foundation
import Testing

@testable import Views

@Suite("spectrumBarRects")
struct SpectrumBarRectsTests {
    private let size = CGSize(width: 100, height: 200)

    @Test("one bar per height, sized to its level")
    func barPerHeight() {
        let bars = spectrumBarRects(
            in: size, heights: [1, 0.5], barWidthRatio: 1, placement: .bottom)
        #expect(bars.count == 2)
        #expect(bars[0].level == 1)
        #expect(abs(bars[0].rect.height - 200) < 0.01)
        #expect(abs(bars[1].rect.height - 100) < 0.01)
    }

    @Test("bars below half a point are dropped")
    func dropsInvisibleBars() {
        // 0.001 * 200 = 0.2 pt < 0.5 → dropped; the tall one stays.
        let bars = spectrumBarRects(
            in: size, heights: [0.001, 1], barWidthRatio: 1, placement: .bottom)
        #expect(bars.count == 1)
        #expect(bars[0].level == 1)
    }

    @Test("bottom placement grows bars up from the bottom edge")
    func bottomAnchors() {
        let bars = spectrumBarRects(
            in: size, heights: [0.5], barWidthRatio: 1, placement: .bottom)
        #expect(abs((bars[0].rect.maxY) - 200) < 0.01)
    }

    @Test("top placement grows bars down from the top edge")
    func topAnchors() {
        let bars = spectrumBarRects(
            in: size, heights: [0.5], barWidthRatio: 1, placement: .top)
        #expect(abs(bars[0].rect.minY) < 0.01)
    }

    @Test("empty heights or zero size yields no bars")
    func emptyInputs() {
        #expect(spectrumBarRects(in: size, heights: [], barWidthRatio: 1, placement: .bottom).isEmpty)
        #expect(
            spectrumBarRects(in: .zero, heights: [1], barWidthRatio: 1, placement: .bottom).isEmpty)
    }
}
