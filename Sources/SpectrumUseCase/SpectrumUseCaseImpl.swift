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
    /// Memoized analyzer plus the per-channel bar count and tap sample rate it
    /// was built for. The displayed bar count is derived from the overlay width
    /// (cava style), so it changes on resize. The sample rate is read from the
    /// tap at construction (#299) and fixed for the tap's lifetime; a tap
    /// recreation (play/pause, source change) picks up any new device rate and
    /// triggers a rebuild via the changed `window.sampleRate`.
    private var analyzer: (bars: Int, sampleRate: Double, engine: any FrequencyAnalyzing)?

    public init() {}
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

    /// The analyzer for the current per-channel bar count and tap sample rate,
    /// rebuilt only when either changes (a window resize or an output-device
    /// rate change); everything else is launch-static.
    private func resolvedAnalyzer(
        for style: SpectrumStyle, bars: Int, sampleRate: Double
    ) -> any FrequencyAnalyzing {
        if let analyzer, analyzer.bars == bars, analyzer.sampleRate == sampleRate {
            return analyzer.engine
        }
        let engine = analyzerFactory.analyzer(
            fftSize: style.fftSize,
            barCount: bars,
            minDb: style.minDb,
            maxDb: style.maxDb,
            linearScale: style.scale == .linear,
            minFrequency: style.minFreq,
            maxFrequency: style.maxFreq,
            sampleRate: sampleRate
        )
        analyzer = (bars, sampleRate, engine)
        return engine
    }
}
