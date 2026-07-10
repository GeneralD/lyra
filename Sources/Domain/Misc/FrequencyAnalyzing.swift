import Dependencies

/// One PCM window → per-bar magnitudes, as consumed by `SpectrumUseCase` on
/// the DisplayLink tick. The live implementation is `FrequencyAnalyzer`'s
/// vDSP FFT pipeline. Deliberately not `Sendable`: the live analyzer holds
/// FFT setup and is confined to the main-thread tick by its owner.
public protocol FrequencyAnalyzing {
    /// Zero-floored magnitudes of one PCM window, one value per bar; 1 marks
    /// the full-scale reference and louder signals exceed it.
    func magnitudes(of samples: [Float]) -> [Float]
}

/// Builds `FrequencyAnalyzing` instances. A factory rather than one injected
/// analyzer because the analyzer is rebuilt at runtime — the bar count
/// follows the overlay width (#297) and the sample rate follows the tap
/// (#299) — and memoizing across rebuilds is the caller's concern.
public protocol FrequencyAnalyzerFactory: Sendable {
    func analyzer(
        fftSize: Int, barCount: Int, minDb: Double, maxDb: Double,
        linearScale: Bool, minFrequency: Double, maxFrequency: Double,
        sampleRate: Double
    ) -> any FrequencyAnalyzing
}

public enum FrequencyAnalyzerFactoryKey: TestDependencyKey {
    public static let testValue: any FrequencyAnalyzerFactory = UnimplementedFrequencyAnalyzerFactory()
}

extension DependencyValues {
    public var frequencyAnalyzerFactory: any FrequencyAnalyzerFactory {
        get { self[FrequencyAnalyzerFactoryKey.self] }
        set { self[FrequencyAnalyzerFactoryKey.self] = newValue }
    }
}

private struct UnimplementedFrequencyAnalyzerFactory: FrequencyAnalyzerFactory {
    func analyzer(
        fftSize: Int, barCount: Int, minDb: Double, maxDb: Double,
        linearScale: Bool, minFrequency: Double, maxFrequency: Double,
        sampleRate: Double
    ) -> any FrequencyAnalyzing {
        fatalError("FrequencyAnalyzerFactory.analyzer not implemented")
    }
}
