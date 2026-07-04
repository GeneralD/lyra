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
    /// Un-gained magnitudes of the newest PCM window, `barCount` bars wide
    /// (derived by the Presenter from the overlay width, cava style). Empty
    /// while nothing is being captured.
    func magnitudes(barCount: Int) -> [Float]
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
    func magnitudes(barCount: Int) -> [Float] { [] }
}
