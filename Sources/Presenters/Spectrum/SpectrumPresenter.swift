import Combine
import Dependencies
import Domain
import Foundation

/// Display state for the spectrum analyzer overlay (#23).
///
/// The DisplayLink calls `tick()` once per frame to fold the newest FFT
/// magnitudes into an exponentially decaying bar array; the View's Canvas
/// reads the result through `binHeights()`, which never mutates state — a
/// Canvas draw closure runs during view update, where publishing changes is
/// illegal. `isAnimating` gates the View's `TimelineView` exactly like
/// `RipplePresenter` (#258): while nothing is captured and every bar has
/// decayed away, the timeline pauses and the Canvas stops redrawing.
@MainActor
public final class SpectrumPresenter: ObservableObject {
    @Dependency(\.spectrumInteractor) private var interactor

    @Published public private(set) var isAnimating = false
    private var currentBins: [Float] = []
    private var capturing = false
    private var cancellable: AnyCancellable?

    public init() {}

    public var isEnabled: Bool { interactor.spectrumStyle.enabled }
    public var style: SpectrumStyle { interactor.spectrumStyle }

    public func start() {
        guard isEnabled else { return }
        interactor.start()
        cancellable = interactor.isCapturing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.capturing = value }
    }

    public func stop() {
        cancellable = nil
        interactor.stop()
        capturing = false
    }

    /// DisplayLink frame tick: merges the newest magnitudes with the decayed
    /// previous frame and updates the animation flag.
    public func tick() {
        guard capturing || !currentBins.isEmpty else { return }
        let style = interactor.spectrumStyle
        let fresh = capturing ? interactor.magnitudes() : []
        let decayed = currentBins.map { $0 * Float(style.decayRate) }
        currentBins = merged(fresh: fresh, decayed: decayed, barCount: style.barCount)
        let animating = capturing || currentBins.contains { $0 > Self.silenceThreshold }
        // Once the falloff finishes, drop the bins entirely so idle ticks can
        // bail out on the guard above without per-frame array work.
        if !animating { currentBins = [] }
        setAnimating(animating)
    }

    /// Bar heights (0…1) for the current frame. Read-only — safe to call from
    /// inside a Canvas draw closure.
    public func binHeights() -> [Float] { currentBins }

    /// Bars below this are treated as fully decayed (~1/4 pixel at 256 pt).
    private static let silenceThreshold: Float = 0.001

    private func merged(fresh: [Float], decayed: [Float], barCount: Int) -> [Float] {
        guard !fresh.isEmpty || !decayed.isEmpty else { return [] }
        return (0..<barCount).map { bar in
            max(bar < fresh.count ? fresh[bar] : 0, bar < decayed.count ? decayed[bar] : 0)
        }
    }

    private func setAnimating(_ value: Bool) {
        guard isAnimating != value else { return }
        isAnimating = value
    }
}
