import Foundation
import Testing

@testable import FrequencyAnalyzer

@Suite("FrequencyAnalyzer")
struct FrequencyAnalyzerTests {
    private static let fftSize = 1024
    private static let barCount = 32

    /// db scale keeps the historical exact-zero and exceeds-1 semantics the
    /// suite's assertions rely on; linear-scale behavior has its own tests.
    /// A band range wide enough (≈ lowest bin … ⅔ Nyquist at 48 kHz) that the
    /// bin positions these tests probe all fall inside the shown spectrum.
    private static let minFreq = 20.0
    private static let maxFreq = 16000.0

    private var analyzer: FrequencyAnalyzer {
        FrequencyAnalyzer(
            fftSize: Self.fftSize, barCount: Self.barCount, minDb: -80, maxDb: 0,
            linearScale: false, minFrequency: Self.minFreq, maxFrequency: Self.maxFreq)
    }

    private var linearAnalyzer: FrequencyAnalyzer {
        FrequencyAnalyzer(
            fftSize: Self.fftSize, barCount: Self.barCount, minDb: -80, maxDb: 0,
            linearScale: true, minFrequency: Self.minFreq, maxFrequency: Self.maxFreq)
    }

    /// A full-scale sine whose frequency lands exactly on FFT bin `bin`.
    private func sine(bin: Int, count: Int = Self.fftSize) -> [Float] {
        (0..<count).map { i in
            sin(2 * .pi * Float(bin) * Float(i) / Float(Self.fftSize))
        }
    }

    @Test("output has one value per bar")
    func barCountMatches() {
        #expect(analyzer.magnitudes(of: sine(bin: 100)).count == Self.barCount)
    }

    /// The bar whose value peaks for a pure sine on the given FFT bin.
    private func peakBar(bin: Int) throws -> Int {
        let bars = analyzer.magnitudes(of: sine(bin: bin))
        return try #require(bars.indices.max { bars[$0] < bars[$1] })
    }

    @Test("bands are log-spaced: equal frequency ratios sit equal bar distances apart")
    func bandsAreLogSpaced() throws {
        // One octave up moves the peak by the same number of bars wherever
        // it starts (in the region where bands span multiple bins).
        let low = try peakBar(bin: 32)
        let mid = try peakBar(bin: 64)
        let high = try peakBar(bin: 128)
        #expect(low < mid)
        #expect(mid - low == high - mid)
    }

    @Test("neighboring bass bins resolve into distinct bars")
    func bassBinsResolve() throws {
        // Linear grouping lumped bins 4 and 8 into one 15-bin-wide bar 0;
        // log bands give the bottom octaves their own bars.
        #expect(try peakBar(bin: 4) != (try peakBar(bin: 8)))
    }

    @Test("silence maps to all-zero bars")
    func silenceIsAllZero() {
        let bars = analyzer.magnitudes(of: [Float](repeating: 0, count: Self.fftSize))
        #expect(bars.allSatisfy { $0 == 0 })
    }

    @Test("fewer samples than the FFT window yields all-zero bars")
    func shortInputIsAllZero() {
        let bars = analyzer.magnitudes(of: sine(bin: 100, count: Self.fftSize / 2))
        #expect(bars.count == Self.barCount)
        #expect(bars.allSatisfy { $0 == 0 })
    }

    @Test("values are floored at 0 and a loud signal exceeds the maxDb reference")
    func loudSignalExceedsReference() {
        // +60 dB over the full-scale sine, whose peak is already above 0.5:
        // without an upper clamp the peak must land beyond 1 (#297 auto-gain
        // relies on this headroom).
        let loud = sine(bin: 100).map { $0 * 1000 }
        let bars = analyzer.magnitudes(of: loud)
        #expect(bars.allSatisfy { $0 >= 0 })
        #expect(bars.contains { $0 > 1 })
    }

    @Test("non-power-of-two fft size is rounded down to a power of two")
    func fftSizeRounding() {
        let rounded = FrequencyAnalyzer(
            fftSize: 1500, barCount: 8, minDb: -80, maxDb: 0, linearScale: false,
            minFrequency: Self.minFreq, maxFrequency: Self.maxFreq)
        // Rounded to 1024: a 1024-sample input must be accepted (non-zero output).
        let bars = rounded.magnitudes(of: sine(bin: 64))
        #expect(bars.contains { $0 > 0 })
    }

    @Test("the linear scale keeps amplitude ratios — the db scale flattens them")
    func linearScaleKeepsRatios() throws {
        // Halving the amplitude must halve the bar: this ratio preservation
        // is what makes quiet bands sit low next to loud ones (#297). The
        // db scale turns the same halving into a small constant offset.
        let loud = try #require(linearAnalyzer.magnitudes(of: sine(bin: 100)).max())
        let quietInput = sine(bin: 100).map { $0 * 0.5 }
        let quiet = try #require(linearAnalyzer.magnitudes(of: quietInput).max())
        #expect(abs(quiet / loud - 0.5) < 0.01)
    }
}
