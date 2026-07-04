import Combine
import Dependencies
import Domain
import Foundation
import Testing

@testable import Presenters

// MARK: - Fake

private final class FakeSpectrumInteractor: SpectrumInteractor, @unchecked Sendable {
    let spectrumStyle: SpectrumStyle
    let capturingSubject = CurrentValueSubject<Bool, Never>(false)
    var magnitudesValue: [Float] = []
    private(set) var startCount = 0
    private(set) var stopCount = 0

    init(style: SpectrumStyle) { self.spectrumStyle = style }

    var isCapturing: AnyPublisher<Bool, Never> { capturingSubject.eraseToAnyPublisher() }
    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
    func magnitudes() -> [Float] { magnitudesValue }
}

// MARK: - Tests

@Suite("SpectrumPresenter")
struct SpectrumPresenterTests {
    /// noiseReduction 0 is cava's passthrough: no integral accumulation and
    /// the gravity release is disabled (`> 0.1` guard), so the first
    /// captured frame shows the input verbatim.
    private static let enabledStyle = SpectrumStyle(enabled: true, barCount: 4, noiseReduction: 0)

    @MainActor
    private static func presenter(with interactor: FakeSpectrumInteractor) -> SpectrumPresenter {
        withDependencies {
            $0.spectrumInteractor = interactor
        } operation: {
            SpectrumPresenter()
        }
    }

    /// Ticks once per poll step until `condition` holds or the deadline hits —
    /// the capturing flag arrives async via the main queue, so fixed sleeps
    /// would be flaky on CI.
    @MainActor
    private static func tickUntil(_ presenter: SpectrumPresenter, _ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(3)
        presenter.tick()
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
            presenter.tick()
        }
    }

    @MainActor
    @Test("isEnabled reflects the interactor style")
    func isEnabledReflectsStyle() {
        let on = Self.presenter(with: FakeSpectrumInteractor(style: Self.enabledStyle))
        #expect(on.isEnabled)
        let off = Self.presenter(with: FakeSpectrumInteractor(style: SpectrumStyle(enabled: false)))
        #expect(!off.isEnabled)
    }

    @MainActor
    @Test("start is inert while the spectrum is disabled")
    func startSkipsWhenDisabled() {
        let interactor = FakeSpectrumInteractor(style: SpectrumStyle(enabled: false))
        Self.presenter(with: interactor).start()
        #expect(interactor.startCount == 0)
    }

    @MainActor
    @Test("start forwards to the interactor when enabled")
    func startForwardsWhenEnabled() {
        let interactor = FakeSpectrumInteractor(style: Self.enabledStyle)
        Self.presenter(with: interactor).start()
        #expect(interactor.startCount == 1)
    }

    @MainActor
    @Test("stop tears the interactor down")
    func stopForwards() {
        let interactor = FakeSpectrumInteractor(style: Self.enabledStyle)
        let presenter = Self.presenter(with: interactor)
        presenter.start()
        presenter.stop()
        #expect(interactor.stopCount == 1)
    }

    @MainActor
    @Test("ticks while capturing surface the magnitudes and animate")
    func capturingTickPublishesBars() async {
        let interactor = FakeSpectrumInteractor(style: Self.enabledStyle)
        interactor.magnitudesValue = [1, 0.5, 0.25, 0.125]
        let presenter = Self.presenter(with: interactor)
        presenter.start()
        interactor.capturingSubject.send(true)

        await Self.tickUntil(presenter) { !presenter.binHeights().isEmpty }
        #expect(presenter.binHeights() == [1, 0.5, 0.25, 0.125])
        #expect(presenter.isAnimating)
    }

    @MainActor
    @Test("after capture ends the bars fall gradually, then clear")
    func barsFallAfterCapture() async {
        // A non-zero noise_reduction arms cava's gravity release; at 0 the
        // release is a passthrough and the bar would blink out in one frame.
        let style = SpectrumStyle(enabled: true, barCount: 1, noiseReduction: 0.77)
        let interactor = FakeSpectrumInteractor(style: style)
        interactor.magnitudesValue = [1]
        let presenter = Self.presenter(with: interactor)
        presenter.start()
        interactor.capturingSubject.send(true)
        await Self.tickUntil(presenter) { !presenter.binHeights().isEmpty }

        // The bar eases down over frames rather than snapping to zero…
        interactor.capturingSubject.send(false)
        await Self.tickUntil(presenter) { (presenter.binHeights().first ?? 1) < 1 }
        let falling = presenter.binHeights().first ?? -1
        #expect(falling > 0 && falling < 1)
        #expect(presenter.isAnimating)

        // …then it reaches zero, the state clears, and the animation gate shuts.
        await Self.tickUntil(presenter) { presenter.binHeights().isEmpty }
        #expect(presenter.binHeights().isEmpty)
        #expect(!presenter.isAnimating)
    }

    @MainActor
    @Test("attack is instant — a rising bar reaches its target on the first frame")
    func attackIsInstant() async {
        // cava adopts a louder value immediately (its smoothing is on the
        // release, not the attack), so the first captured frame already
        // shows the input — no easing ramp on the way up.
        let interactor = FakeSpectrumInteractor(style: Self.enabledStyle)
        interactor.magnitudesValue = [0.4, 0, 0, 0]
        let presenter = Self.presenter(with: interactor)
        presenter.start()
        interactor.capturingSubject.send(true)

        await Self.tickUntil(presenter) { !presenter.binHeights().isEmpty }
        #expect(abs((presenter.binHeights().first ?? 0) - 0.4) < 0.001)
    }

    @MainActor
    @Test("ticks with nothing captured and no residue are inert")
    func idleTickIsInert() {
        let presenter = Self.presenter(with: FakeSpectrumInteractor(style: Self.enabledStyle))
        presenter.start()
        presenter.tick()
        #expect(presenter.binHeights().isEmpty)
        #expect(!presenter.isAnimating)
    }
}
