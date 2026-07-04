import Dependencies

/// Business logic for the spectrum analyzer (#23): drives the audio capture
/// lifecycle and converts the newest captured PCM window into normalized
/// per-bar magnitudes.
public protocol SpectrumUseCase: Sendable {
    /// Starts capturing the process's audio, replacing any active capture.
    /// Returns `false` when capture is unavailable — OS below the macOS 14.4
    /// floor, TCC denial, unknown process, or a CoreAudio error.
    func startCapture(pid: Int) async -> Bool
    /// Tears down the active capture, if any. Safe to call repeatedly.
    func stopCapture() async
    /// Un-gained per-bar magnitudes of the newest PCM window, `barCount` bars
    /// wide (derived from the overlay width, cava style). Empty while nothing
    /// is captured or `barCount` is 0. The Presenter applies cava's autosens
    /// scaling and clamps to 0…1 (#297).
    func magnitudes(style: SpectrumStyle, barCount: Int) -> [Float]
}

public enum SpectrumUseCaseKey: TestDependencyKey {
    public static let testValue: any SpectrumUseCase = UnimplementedSpectrumUseCase()
}

extension DependencyValues {
    public var spectrumUseCase: any SpectrumUseCase {
        get { self[SpectrumUseCaseKey.self] }
        set { self[SpectrumUseCaseKey.self] = newValue }
    }
}

private struct UnimplementedSpectrumUseCase: SpectrumUseCase {
    func startCapture(pid: Int) async -> Bool { false }
    func stopCapture() async {}
    func magnitudes(style: SpectrumStyle, barCount: Int) -> [Float] { [] }
}
