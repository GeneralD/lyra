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
    /// decayRate 0.5 keeps decay math exact in Float and short in test time.
    private static let enabledStyle = SpectrumStyle(enabled: true, barCount: 4, decayRate: 0.5)

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
    @Test("after capture ends the bars decay by decayRate, then clear")
    func barsDecayAfterCapture() async {
        let interactor = FakeSpectrumInteractor(style: Self.enabledStyle)
        interactor.magnitudesValue = [1]
        let presenter = Self.presenter(with: interactor)
        presenter.start()
        interactor.capturingSubject.send(true)
        await Self.tickUntil(presenter) { !presenter.binHeights().isEmpty }

        // While the capturing flag is still propagating, ticks keep the bar at
        // 1 (fresh wins the max-merge); the first tick after it lands yields
        // exactly one decay step.
        interactor.capturingSubject.send(false)
        await Self.tickUntil(presenter) { (presenter.binHeights().first ?? 1) < 1 }
        #expect(presenter.binHeights().first == 0.5)
        #expect(presenter.isAnimating)

        // Keep ticking: 0.5 halves per frame and falls under the silence
        // threshold, at which point the bins clear and the animation gate shuts.
        await Self.tickUntil(presenter) { presenter.binHeights().isEmpty }
        #expect(presenter.binHeights().isEmpty)
        #expect(!presenter.isAnimating)
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
