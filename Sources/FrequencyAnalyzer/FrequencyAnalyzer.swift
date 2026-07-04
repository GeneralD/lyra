import Accelerate

/// Pure PCM-window → per-bar magnitude conversion for the spectrum analyzer
/// (#23): Hann window → real FFT → power spectrum → per-bin scaling →
/// log-frequency grouping into `barCount` bars. A value of 1 marks the
/// full-scale reference, so the caller can auto-gain against the running
/// peak (#297). Two scales (#297):
///
/// - **linear** (cava's look): height tracks amplitude, weighted by
///   frequency so music's natural ~1/f rolloff doesn't bury the mids and
///   treble (cava's eq). Quiet bands stay near zero, loud ones tower.
/// - **db**: decibels map linearly into height — flat, carpet-like, but
///   readable for wide-dynamic material.
///
/// Stateless between calls, so the same input always yields the same
/// output — smoothing (decay) is the Presenter's display concern, not this
/// module's.
public struct FrequencyAnalyzer {
    private let fftSize: Int
    private let barCount: Int
    private let minDb: Float
    private let maxDb: Float
    private let linearScale: Bool
    private let fft: vDSP.FFT<DSPSplitComplex>?
    private let window: [Float]
    private let bands: [Range<Int>]
    private let binWeights: [Float]

    /// - Parameters:
    ///   - fftSize: window length in samples; rounded down to a power of two.
    ///   - barCount: number of output bars.
    ///   - minDb: power level mapped to magnitude 0 (db scale only).
    ///   - maxDb: power level mapped to magnitude 1 (db scale only; louder
    ///     exceeds 1).
    ///   - linearScale: amplitude-proportional heights with frequency
    ///     weighting instead of the db mapping.
    public init(fftSize: Int, barCount: Int, minDb: Double, maxDb: Double, linearScale: Bool) {
        let clampedSize = max(64, fftSize)
        let log2n = vDSP_Length(63 - UInt64(clampedSize).leadingZeroBitCount)
        self.fftSize = 1 << log2n
        self.barCount = max(1, barCount)
        self.minDb = Float(minDb)
        self.maxDb = Float(max(maxDb, minDb + 1))
        self.fft = vDSP.FFT(log2n: log2n, radix: .radix2, ofType: DSPSplitComplex.self)
        self.window = vDSP.window(
            ofType: Float.self, usingSequence: .hanningDenormalized,
            count: 1 << log2n, isHalfWindow: false
        )
        self.linearScale = linearScale
        let binCount = max(1, (1 << log2n) / 2 - 1)
        self.bands = Self.logBands(barCount: self.barCount, binCount: binCount)
        // Frequency weighting for the linear scale (cava's eq), anchored at
        // the LOWEST bin (weight 1) and rising with frequency: bass keeps
        // its raw amplitude while mids and treble are boosted to counter
        // music's ~1/f rolloff. Anchoring at the top instead would crush
        // every musical value and pin the bars near zero.
        self.binWeights = (0..<binCount).map { bin in
            pow(Float(bin + 1), Self.trebleExponent)
        }
    }

    /// Zero-floored magnitudes of one PCM window, one value per bar; 1 marks
    /// the `maxDb` reference and louder signals exceed it. Returns all-zero
    /// bars when fewer than `fftSize` samples are supplied.
    public func magnitudes(of samples: [Float]) -> [Float] {
        let silence = [Float](repeating: 0, count: barCount)
        guard let fft, samples.count >= fftSize else { return silence }

        let windowed = vDSP.multiply(samples[(samples.count - fftSize)...], window)
        let power = powerSpectrum(of: windowed, using: fft)
        return bars(grouping: linearScale ? linearValues(power) : dbValues(power))
    }

    /// Amplitude-proportional per-bin values: 1 = a full-scale sine at the
    /// lowest band; higher bands are boosted by the frequency tilt so the
    /// linear scale doesn't show bass only.
    private func linearValues(_ power: [Float]) -> [Float] {
        let fullScale = Float(fftSize) / 2
        return zip(power, binWeights).map { value, weight in
            sqrt(value) / fullScale * weight
        }
    }

    /// Decibels mapped linearly into 0…, zero-floored at `minDb`, 1 at the
    /// `maxDb` reference with louder signals exceeding it.
    private func dbValues(_ power: [Float]) -> [Float] {
        let range = maxDb - minDb
        return power.map { value in
            let db = 10 * log10(max(value, .leastNormalMagnitude))
            return max((db - minDb) / range, 0)
        }
    }

    /// Exponent of the linear scale's frequency weighting — cava's eq tilt.
    private static let trebleExponent: Float = 0.6

    /// Half-spectrum power values (DC bin dropped) of a windowed sample block.
    private func powerSpectrum(of windowed: [Float], using fft: vDSP.FFT<DSPSplitComplex>) -> [Float] {
        let halfN = fftSize / 2
        var inputReal = [Float](repeating: 0, count: halfN)
        var inputImaginary = [Float](repeating: 0, count: halfN)
        var outputReal = [Float](repeating: 0, count: halfN)
        var outputImaginary = [Float](repeating: 0, count: halfN)
        var power = [Float](repeating: 0, count: halfN)

        inputReal.withUnsafeMutableBufferPointer { inRealPtr in
            inputImaginary.withUnsafeMutableBufferPointer { inImagPtr in
                outputReal.withUnsafeMutableBufferPointer { outRealPtr in
                    outputImaginary.withUnsafeMutableBufferPointer { outImagPtr in
                        var input = DSPSplitComplex(
                            realp: inRealPtr.baseAddress!, imagp: inImagPtr.baseAddress!)
                        var output = DSPSplitComplex(
                            realp: outRealPtr.baseAddress!, imagp: outImagPtr.baseAddress!)
                        windowed.withUnsafeBufferPointer { samplePtr in
                            samplePtr.baseAddress!.withMemoryRebound(
                                to: DSPComplex.self, capacity: halfN
                            ) {
                                vDSP_ctoz($0, 2, &input, 1, vDSP_Length(halfN))
                            }
                        }
                        fft.forward(input: input, output: &output)
                        vDSP.squareMagnitudes(output, result: &power)
                    }
                }
            }
        }
        // Drop the DC bin — overall loudness offset, not a frequency band.
        return Array(power.dropFirst())
    }

    /// Groups the half-spectrum into the precomputed log bands, taking each
    /// band's maximum so narrow peaks stay visible.
    private func bars(grouping values: [Float]) -> [Float] {
        bands.map { band in values[band].max() ?? 0 }
    }

    /// Upper edge of the analyzed range as a fraction of Nyquist — ≈16 kHz
    /// at the typical 48 kHz tap rate. Music carries almost nothing above
    /// it, so bars there would sit permanently near zero.
    private static let upperBandRatio = 2.0 / 3.0

    /// Log-spaced power-array bands, one per bar: every bar spans an equal
    /// RATIO of frequency, the way hearing does (and cava). Linear grouping
    /// is what made every song render the same silhouette — nearly all
    /// musical energy landed in the first few bars while the rest showed
    /// the near-static treble floor. Each band is at least one bin wide, so
    /// the lowest bars resolve single FFT bins; bands left without bins
    /// (absurdly high `barCount`) come out empty and render zero.
    private static func logBands(barCount: Int, binCount: Int) -> [Range<Int>] {
        let top = Double(max(barCount, Int((Double(binCount) * upperBandRatio).rounded())))
        return (0..<barCount).reduce(into: [Range<Int>]()) { bands, bar in
            let start = bands.last?.upperBound ?? 0
            let edge = Int(pow(top, Double(bar + 1) / Double(barCount)).rounded())
            bands.append(start..<min(max(edge, start + 1), max(start, binCount)))
        }
    }
}
