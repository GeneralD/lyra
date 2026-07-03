import Accelerate

/// Pure PCM-window → per-bar magnitude conversion for the spectrum analyzer
/// (#23): Hann window → real FFT → power spectrum → dB → 0…1 normalization →
/// linear grouping into `barCount` bars. Stateless between calls, so the same
/// input always yields the same output — smoothing (decay) is the Presenter's
/// display concern, not this module's.
public struct FrequencyAnalyzer {
    private let fftSize: Int
    private let barCount: Int
    private let minDb: Float
    private let maxDb: Float
    private let fft: vDSP.FFT<DSPSplitComplex>?
    private let window: [Float]

    /// - Parameters:
    ///   - fftSize: window length in samples; rounded down to a power of two.
    ///   - barCount: number of output bars.
    ///   - minDb: power level mapped to bar height 0.
    ///   - maxDb: power level mapped to bar height 1.
    public init(fftSize: Int, barCount: Int, minDb: Double, maxDb: Double) {
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
    }

    /// Normalized (0…1) magnitudes of one PCM window, one value per bar.
    /// Returns all-zero bars when fewer than `fftSize` samples are supplied.
    public func magnitudes(of samples: [Float]) -> [Float] {
        let silence = [Float](repeating: 0, count: barCount)
        guard let fft, samples.count >= fftSize else { return silence }

        let windowed = vDSP.multiply(samples[(samples.count - fftSize)...], window)
        let power = powerSpectrum(of: windowed, using: fft)
        let range = maxDb - minDb
        let normalized = power.map { value in
            let db = 10 * log10(max(value, .leastNormalMagnitude))
            return min(max((db - minDb) / range, 0), 1)
        }
        return bars(grouping: normalized)
    }

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

    /// Groups the half-spectrum linearly into `barCount` bars, taking each
    /// group's maximum so narrow peaks stay visible.
    private func bars(grouping values: [Float]) -> [Float] {
        let groupSize = max(1, values.count / barCount)
        return (0..<barCount).map { bar in
            let start = bar * groupSize
            guard start < values.count else { return 0 }
            let end = min(start + groupSize, values.count)
            return values[start..<end].max() ?? 0
        }
    }
}
