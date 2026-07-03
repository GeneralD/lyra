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
    /// Normalized magnitudes (0…1) of the newest PCM window, one per bar.
    /// Empty while nothing is being captured.
    func magnitudes(style: SpectrumStyle) -> [Float]
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
    func magnitudes(style: SpectrumStyle) -> [Float] { [] }
}
