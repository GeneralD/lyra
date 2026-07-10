import Domain

extension FrequencyAnalyzer: FrequencyAnalyzing {}

/// Live `FrequencyAnalyzerFactory`: builds the vDSP-backed
/// `FrequencyAnalyzer`. Pure forwarding — every parameter maps 1:1 onto the
/// analyzer's initializer.
public struct LiveFrequencyAnalyzerFactory {
    public init() {}
}

extension LiveFrequencyAnalyzerFactory: FrequencyAnalyzerFactory {
    public func analyzer(
        fftSize: Int, barCount: Int, minDb: Double, maxDb: Double,
        linearScale: Bool, minFrequency: Double, maxFrequency: Double,
        sampleRate: Double
    ) -> any FrequencyAnalyzing {
        FrequencyAnalyzer(
            fftSize: fftSize, barCount: barCount, minDb: minDb, maxDb: maxDb,
            linearScale: linearScale, minFrequency: minFrequency,
            maxFrequency: maxFrequency, sampleRate: sampleRate)
    }
}
