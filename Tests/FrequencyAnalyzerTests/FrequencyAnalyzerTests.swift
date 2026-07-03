import Foundation
import Testing

@testable import FrequencyAnalyzer

@Suite("FrequencyAnalyzer")
struct FrequencyAnalyzerTests {
    private static let fftSize = 1024
    private static let barCount = 32

    private var analyzer: FrequencyAnalyzer {
        FrequencyAnalyzer(fftSize: Self.fftSize, barCount: Self.barCount, minDb: -80, maxDb: 0)
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

    @Test("a pure sine peaks in the bar containing its frequency bin")
    func sinePeaksInExpectedBar() throws {
        let targetBin = 100
        let bars = analyzer.magnitudes(of: sine(bin: targetBin))
        // Half spectrum with DC dropped (511 values) grouped into 32 bars of
        // 15 bins: FFT bin 100 sits at array index 99 → bar 6.
        let expectedBar = (targetBin - 1) / max(1, (Self.fftSize / 2 - 1) / Self.barCount)
        let peakBar = try #require(bars.indices.max { bars[$0] < bars[$1] })
        #expect(peakBar == expectedBar)
        #expect(bars[peakBar] > 0.5)
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

    @Test("values stay clamped to 0...1 even for a loud signal")
    func valuesAreClamped() {
        let loud = sine(bin: 100).map { $0 * 4 }
        let bars = analyzer.magnitudes(of: loud)
        #expect(bars.allSatisfy { (0...1).contains($0) })
    }

    @Test("non-power-of-two fft size is rounded down to a power of two")
    func fftSizeRounding() {
        let rounded = FrequencyAnalyzer(fftSize: 1500, barCount: 8, minDb: -80, maxDb: 0)
        // Rounded to 1024: a 1024-sample input must be accepted (non-zero output).
        let bars = rounded.magnitudes(of: sine(bin: 64))
        #expect(bars.contains { $0 > 0 })
    }
}
