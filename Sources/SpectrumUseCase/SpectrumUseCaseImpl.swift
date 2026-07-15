import Dependencies
import Domain

/// Business logic for the spectrum analyzer (#23): forwards the capture
/// lifecycle to the repository and converts the newest PCM window into
/// per-bar magnitudes via the injected `FrequencyAnalyzing` (#297). The heights
/// are un-gained here — cava's autosens and smoothing live in the Presenter,
/// which scales and clamps them per frame. In stereo the two channels are
/// analyzed separately and mirrored around the center, cava-style — lowest
/// bands meet in the middle; mono averages them first.
///
/// `@unchecked` only because of the memoized `analyzer`, which is touched
/// solely from the main-thread DisplayLink tick via `magnitudes(style:)`.
public final class SpectrumUseCaseImpl: @unchecked Sendable {
    // Stored wrapper captures the dependency context at init, so instances
    // built inside `withDependencies` keep their fakes when methods run
    // outside that scope.
    @Dependency(\.audioCaptureRepository) private var repository
    @Dependency(\.frequencyAnalyzerFactory) private var analyzerFactory
    /// Memoized analyzer plus the full set of build inputs it was created for.
    /// The displayed bar count is derived from the overlay width (cava style),
    /// so it changes on resize; the sample rate is read from the tap at
    /// construction (#299) and fixed for the tap's lifetime, so a tap recreation
    /// (play/pause, source change) picks up any new device rate. The band
    /// settings (`fft_size`, `min_db`/`max_db`, `scale`, `min_freq`/`max_freq`)
    /// can now change live via config hot-reload (#41 PR3), so they are part of
    /// the memo key too — keying on only bars+sampleRate silently reused the old
    /// engine and ignored those edits until a resize/restart (#41 PR3 review, F5).
    private var analyzer: (spec: AnalyzerSpec, engine: any FrequencyAnalyzing)?

    public init() {}
}

/// The full set of inputs `FrequencyAnalyzerFactory.analyzer(...)` is built
/// from, so the memo invalidates the instant any one of them changes.
private struct AnalyzerSpec: Equatable {
    let fftSize: Int
    let bars: Int
    let minDb: Double
    let maxDb: Double
    let linearScale: Bool
    let minFrequency: Double
    let maxFrequency: Double
    let sampleRate: Double
}

extension SpectrumUseCaseImpl: SpectrumUseCase {
    public func startCapture(pid: Int) async -> Bool {
        await repository.startCapture(pid: pid)
    }

    public func stopCapture() async {
        await repository.stopCapture()
    }

    public func magnitudes(style: SpectrumStyle, barCount: Int) -> [Float] {
        rawMagnitudes(style: style, barCount: barCount)
    }
}

extension SpectrumUseCaseImpl {
    /// Un-gained per-bar magnitudes of the newest window, `barCount` bars
    /// wide (derived from the overlay width). Stereo mirrors the left channel
    /// onto the left half and appends the right channel, so the lowest bands
    /// of both meet in the center (cava's stereo layout); mono averages the
    /// channels into one full-width row.
    private func rawMagnitudes(style: SpectrumStyle, barCount: Int) -> [Float] {
        guard barCount > 0 else { return [] }
        let window = repository.latestSamples(count: style.fftSize)
        guard !window.left.isEmpty else { return [] }
        // Stereo gives each channel half of the displayed bars.
        let perChannel = style.stereo ? max(1, barCount / 2) : barCount
        let analyzer = resolvedAnalyzer(for: style, bars: perChannel, sampleRate: window.sampleRate)
        guard style.stereo else {
            return analyzer.magnitudes(of: zip(window.left, window.right).map { ($0 + $1) / 2 })
        }
        return analyzer.magnitudes(of: window.left).reversed()
            + analyzer.magnitudes(of: window.right)
    }

    /// The analyzer for the current per-channel bar count, tap sample rate, and
    /// live band settings — rebuilt the moment any of them changes (a window
    /// resize, an output-device rate change, or a config hot-reload of the band
    /// parameters, #41 PR3 review, F5).
    private func resolvedAnalyzer(
        for style: SpectrumStyle, bars: Int, sampleRate: Double
    ) -> any FrequencyAnalyzing {
        let spec = AnalyzerSpec(
            fftSize: style.fftSize,
            bars: bars,
            minDb: style.minDb,
            maxDb: style.maxDb,
            linearScale: style.scale == .linear,
            minFrequency: style.minFreq,
            maxFrequency: style.maxFreq,
            sampleRate: sampleRate
        )
        if let analyzer, analyzer.spec == spec {
            return analyzer.engine
        }
        let engine = analyzerFactory.analyzer(
            fftSize: spec.fftSize,
            barCount: spec.bars,
            minDb: spec.minDb,
            maxDb: spec.maxDb,
            linearScale: spec.linearScale,
            minFrequency: spec.minFrequency,
            maxFrequency: spec.maxFrequency,
            sampleRate: spec.sampleRate
        )
        analyzer = (spec, engine)
        return engine
    }
}
