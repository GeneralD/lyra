import Combine
import Dependencies

/// Drives the spectrum analyzer overlay (#23): follows the now-playing audio
/// source, manages the process tap lifecycle, and converts captured PCM into
/// per-bar magnitudes.
public protocol SpectrumInteractor: Sendable {
    var spectrumStyle: SpectrumStyle { get }
    /// Emits whether the process tap is actively capturing audio. The
    /// Presenter maps this to its animation state.
    var isCapturing: AnyPublisher<Bool, Never> { get }
    /// Begins observing the now-playing audio source and managing the tap.
    func start()
    /// Tears down the subscription and any active tap.
    func stop()
    /// Normalized magnitudes (0…1) of the newest PCM window, one per bar.
    /// Empty while nothing is being captured.
    func magnitudes() -> [Float]
}

public enum SpectrumInteractorKey: TestDependencyKey {
    public static let testValue: any SpectrumInteractor = UnimplementedSpectrumInteractor()
}

extension DependencyValues {
    public var spectrumInteractor: any SpectrumInteractor {
        get { self[SpectrumInteractorKey.self] }
        set { self[SpectrumInteractorKey.self] = newValue }
    }
}

private struct UnimplementedSpectrumInteractor: SpectrumInteractor {
    var spectrumStyle: SpectrumStyle { .init() }
    var isCapturing: AnyPublisher<Bool, Never> { Empty().eraseToAnyPublisher() }
    func start() {}
    func stop() {}
    func magnitudes() -> [Float] { [] }
}
