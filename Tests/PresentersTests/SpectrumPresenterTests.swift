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
    func magnitudes(barCount: Int) -> [Float] { magnitudesValue }
}

// MARK: - Tests

@Suite("SpectrumPresenter")
struct SpectrumPresenterTests {
    /// noiseReduction 0 is cava's passthrough: no integral accumulation and
    /// the gravity release is disabled (`> 0.1` guard), so the first captured
    /// frame shows the input verbatim. Mono with a 1 pt bar and no gap makes
    /// the derived bar count equal to the reported render width, so a test
    /// gets exactly `N` bars by reporting width `N`.
    private static let enabledStyle = SpectrumStyle(
        enabled: true, stereo: false, barWidth: 1, barSpacing: 0, noiseReduction: 0)

    @MainActor
    private static func presenter(with interactor: FakeSpectrumInteractor) -> SpectrumPresenter {
        withDependencies {
            $0.spectrumInteractor = interactor
        } operation: {
            SpectrumPresenter()
        }
    }

    /// Ticks the presenter until `condition` holds, bounded by a generous
    /// tick *budget* rather than a wall clock. The capturing flag arrives
    /// async on the main queue, so a 1 ms sleep between ticks drains it — but
    /// termination counts ticks, not seconds, so a loaded CI running the
    /// physics slower simply takes longer instead of tripping a deadline and
    /// flaking. The fall from cava's ~4× integrator overshoot down past full
    /// height needs many frames, and that descent is exactly the case a
    /// wall-clock deadline used to lose under load.
    @MainActor
    private static func tickUntil(
        _ presenter: SpectrumPresenter, within maxTicks: Int = 4000, _ condition: () -> Bool
    ) async {
        for _ in 0..<maxTicks {
            presenter.tick()
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
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
        presenter.updateBarTrackLength(4)
        interactor.capturingSubject.send(true)

        await Self.tickUntil(presenter) { !presenter.binHeights().isEmpty }
        #expect(presenter.binHeights() == [1, 0.5, 0.25, 0.125])
        #expect(presenter.isAnimating)
    }

    @MainActor
    @Test("the bar count is derived from the reported width (cava style)")
    func barCountFollowsWidth() async {
        // mono, 1 pt bar + 1 pt gap → slot 2 → count = (width + 1) / 2.
        let style = SpectrumStyle(
            enabled: true, stereo: false, barWidth: 1, barSpacing: 1, noiseReduction: 0)
        let interactor = FakeSpectrumInteractor(style: style)
        interactor.magnitudesValue = [Float](repeating: 1, count: 100)
        let presenter = Self.presenter(with: interactor)
        presenter.start()
        presenter.updateBarTrackLength(21)  // (21 + 1) / 2 = 11 bars
        interactor.capturingSubject.send(true)

        await Self.tickUntil(presenter) { !presenter.binHeights().isEmpty }
        #expect(presenter.binHeights().count == 11)
    }

    @MainActor
    @Test("stereo rounds the derived count down to even")
    func stereoCountIsEven() async {
        let style = SpectrumStyle(
            enabled: true, stereo: true, barWidth: 1, barSpacing: 0, noiseReduction: 0)
        let interactor = FakeSpectrumInteractor(style: style)
        interactor.magnitudesValue = [Float](repeating: 1, count: 100)
        let presenter = Self.presenter(with: interactor)
        presenter.start()
        presenter.updateBarTrackLength(15)  // slot 1 → 15 → even → 14
        interactor.capturingSubject.send(true)

        await Self.tickUntil(presenter) { !presenter.binHeights().isEmpty }
        #expect(presenter.binHeights().count == 14)
    }

    @MainActor
    @Test("no width reported yet yields no bars")
    func zeroWidthNoBars() async {
        let interactor = FakeSpectrumInteractor(style: Self.enabledStyle)
        interactor.magnitudesValue = [1, 1, 1, 1]
        let presenter = Self.presenter(with: interactor)
        presenter.start()
        interactor.capturingSubject.send(true)

        // Capturing flips isAnimating on, but with width 0 the derived count
        // is 0, so there is nothing to draw until the View reports a width.
        await Self.tickUntil(presenter) { presenter.isAnimating }
        #expect(presenter.binHeights().isEmpty)
    }

    @MainActor
    @Test("after capture ends the bars fall gradually, then clear")
    func barsFallAfterCapture() async {
        // A non-zero noise_reduction arms cava's gravity release; at 0 the
        // release is a passthrough and the bar would blink out in one frame.
        let style = SpectrumStyle(
            enabled: true, stereo: false, barWidth: 1, barSpacing: 0, noiseReduction: 0.77)
        let interactor = FakeSpectrumInteractor(style: style)
        interactor.magnitudesValue = [1]
        let presenter = Self.presenter(with: interactor)
        presenter.start()
        presenter.updateBarTrackLength(1)
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
        presenter.updateBarTrackLength(4)
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

    // MARK: - framerate-independent smoothing (#299)

    @Test("framerate constants match the legacy 60 fps tuning at a 60 fps frame")
    func framerateConstantsAt60fps() {
        let c = spectrumFramerateConstants(frameInterval: 1.0 / 60)
        // The old code hardcoded framerate_mod = 66/60; the default frame
        // preserves it exactly, so 60 Hz behavior is unchanged.
        #expect(abs(c.framerateMod - Float(66.0 / 60.0)) < 1e-5)
        #expect(abs(c.integralMod - pow(c.framerateMod, 0.1)) < 1e-6)
        #expect(abs(c.gravityScale - pow(c.framerateMod, 2.5) * 2) < 1e-6)
    }

    @Test("a 120 Hz frame halves framerate_mod versus 60 Hz")
    func framerateConstantsAt120fps() {
        let at120 = spectrumFramerateConstants(frameInterval: 1.0 / 120)
        let at60 = spectrumFramerateConstants(frameInterval: 1.0 / 60)
        #expect(abs(at120.framerateMod - Float(66.0 / 120.0)) < 1e-5)
        #expect(abs(at120.framerateMod - at60.framerateMod / 2) < 1e-5)
    }

    @Test("an absurd frame interval clamps the derived rate to 24…240 fps")
    func framerateConstantsClamp() {
        // Zero / negative → 240 fps ceiling; a 1 fps interval → 24 fps floor.
        #expect(abs(spectrumFramerateConstants(frameInterval: 0).framerateMod - Float(66.0 / 240)) < 1e-5)
        #expect(abs(spectrumFramerateConstants(frameInterval: -5).framerateMod - Float(66.0 / 240)) < 1e-5)
        #expect(abs(spectrumFramerateConstants(frameInterval: 1).framerateMod - Float(66.0 / 24)) < 1e-5)
    }

    @Test("a non-finite frame interval falls back to the 60 fps reference")
    func framerateConstantsNonFinite() {
        // NaN / ±infinity frame timestamps propagate through min/max, so without
        // an explicit finiteness guard they'd poison the smoothing constants.
        let reference = spectrumFramerateConstants(frameInterval: 1.0 / 60)
        for interval in [Double.nan, .infinity, -.infinity] {
            let c = spectrumFramerateConstants(frameInterval: interval)
            #expect(c.framerateMod.isFinite)
            #expect(c == reference)
        }
    }

    @MainActor
    @Test("the fall is refresh-rate independent — 120 Hz needs more frames to clear than 60 Hz")
    func fallIsRefreshRateIndependent() async {
        // A 120 Hz frame advances half a 60 Hz frame's worth of decay, so a
        // bar left to fall takes more frames to clear at 120 Hz — the point of
        // deriving the smoothing constants from the real frame interval.
        func framesToClear(frameInterval: Double) async -> Int {
            let style = SpectrumStyle(
                enabled: true, stereo: false, barWidth: 1, barSpacing: 0, noiseReduction: 0.77)
            let interactor = FakeSpectrumInteractor(style: style)
            interactor.magnitudesValue = [0.5]
            let presenter = Self.presenter(with: interactor)
            presenter.start()
            presenter.updateBarTrackLength(1)
            interactor.capturingSubject.send(true)
            await Self.tickUntil(presenter) { !presenter.binHeights().isEmpty }
            // Let the capturing flag settle (async via the main queue) and the
            // bar start falling at the default 60 fps, so both runs begin the
            // counted portion from the same sub-0.5 state.
            interactor.capturingSubject.send(false)
            await Self.tickUntil(presenter) { (presenter.binHeights().first ?? 1) < 0.5 }

            var frames = 0
            let deadline = ContinuousClock.now + .seconds(3)
            while !presenter.binHeights().isEmpty, ContinuousClock.now < deadline {
                presenter.tick(frameInterval: frameInterval)
                frames += 1
            }
            return frames
        }
        let at120 = await framesToClear(frameInterval: 1.0 / 120)
        let at60 = await framesToClear(frameInterval: 1.0 / 60)
        #expect(at120 > at60)
    }
}
