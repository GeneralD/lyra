import Dependencies
import Domain
import FrequencyAnalyzer

/// Business logic for the spectrum analyzer (#23): forwards the capture
/// lifecycle to the repository and converts the newest PCM window into
/// per-bar magnitudes via the pure `FrequencyAnalyzer` (#297). The heights
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
    private var analyzer: FrequencyAnalyzer?

    public init() {}
}

extension SpectrumUseCaseImpl: SpectrumUseCase {
    public func startCapture(pid: Int) async -> Bool {
        await repository.startCapture(pid: pid)
    }

    public func stopCapture() async {
        await repository.stopCapture()
    }

    public func magnitudes(style: SpectrumStyle) -> [Float] {
        rawMagnitudes(style: style)
    }
}

extension SpectrumUseCaseImpl {
    /// Un-gained per-bar magnitudes of the newest window. Stereo mirrors the
    /// left channel onto the left half and appends the right channel, so the
    /// lowest bands of both meet in the center (cava's stereo layout); mono
    /// averages the channels into one full-width row.
    private func rawMagnitudes(style: SpectrumStyle) -> [Float] {
        let window = repository.latestSamples(count: style.fftSize)
        guard !window.left.isEmpty else { return [] }
        let analyzer = resolvedAnalyzer(for: style)
        guard style.stereo else {
            return analyzer.magnitudes(of: zip(window.left, window.right).map { ($0 + $1) / 2 })
        }
        return analyzer.magnitudes(of: window.left).reversed()
            + analyzer.magnitudes(of: window.right)
    }

    /// Config is launch-static, so the first style builds the one analyzer
    /// used for the rest of the process lifetime. Stereo gives each channel
    /// half of the displayed bars.
    private func resolvedAnalyzer(for style: SpectrumStyle) -> FrequencyAnalyzer {
        guard let analyzer else {
            let built = FrequencyAnalyzer(
                fftSize: style.fftSize,
                barCount: style.stereo ? max(1, style.barCount / 2) : style.barCount,
                minDb: style.minDb,
                maxDb: style.maxDb,
                linearScale: style.scale == .linear
            )
            self.analyzer = built
            return built
        }
        return analyzer
    }
}
