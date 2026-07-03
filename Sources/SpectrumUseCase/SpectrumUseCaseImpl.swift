import Dependencies
import Domain
import FrequencyAnalyzer

/// Business logic for the spectrum analyzer (#23): forwards the capture
/// lifecycle to the repository and converts the newest PCM window into
/// per-bar magnitudes via the pure `FrequencyAnalyzer`.
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
        let samples = repository.latestSamples(count: style.fftSize)
        guard !samples.isEmpty else { return [] }
        return resolvedAnalyzer(for: style).magnitudes(of: samples)
    }
}

extension SpectrumUseCaseImpl {
    /// Config is launch-static, so the first style builds the one analyzer
    /// used for the rest of the process lifetime.
    private func resolvedAnalyzer(for style: SpectrumStyle) -> FrequencyAnalyzer {
        guard let analyzer else {
            let built = FrequencyAnalyzer(
                fftSize: style.fftSize,
                barCount: style.barCount,
                minDb: style.minDb,
                maxDb: style.maxDb
            )
            self.analyzer = built
            return built
        }
        return analyzer
    }
}
