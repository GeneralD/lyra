import Combine
import Dependencies
import Domain
import Foundation

/// Display state for the spectrum analyzer overlay (#23).
///
/// The DisplayLink calls `tick()` once per frame to run a faithful port of
/// cava's bar smoothing over the newest FFT magnitudes (#297; cavacore.c,
/// MIT): sensitivity scaling → gravity release → leaky-integral
/// accumulation → clamp at full height, with the sensitivity auto-tuned
/// from overshoot (cava's autosens). The integral deliberately does NOT
/// normalize its input — sustained energy compounds toward
/// 1/(1-noiseReduction) times a single frame's height (≈4× at 0.77), which
/// is why beats tower over one-frame transients. The View's Canvas
/// reads the result through `binHeights()`, which never mutates state — a
/// Canvas draw closure runs during view update, where publishing changes is
/// illegal. `isAnimating` gates the View's `TimelineView` exactly like
/// `RipplePresenter` (#258): while nothing is captured and every bar has
/// fallen away, the timeline pauses and the Canvas stops redrawing.
@MainActor
public final class SpectrumPresenter: ObservableObject {
    /// Per-bar filter state: `mem` is the leaky-integral accumulator (the
    /// View draws `min(mem, 1)`; beyond 1 counts as overshoot), `prev` the
    /// last pre-integral value (the falloff comparison input), `peak`/`fall`
    /// the gravity ramp (height at fall start, frames since).
    private struct BarMotion {
        var mem: Float = 0
        var prev: Float = 0
        var peak: Float = 0
        var fall: Float = 0
    }

    @Dependency(\.spectrumInteractor) private var interactor
    @Dependency(\.configInteractor) private var configInteractor

    @Published public private(set) var isAnimating = false
    private var motion: [BarMotion] = []
    private var capturing = false
    private var cancellables: Set<AnyCancellable> = []
    /// The full spectrum style last applied by `applyStyle()`. Diffed against a
    /// hot-reload ping so an unrelated config edit is a no-op, an `enabled` toggle
    /// drives the capture lifecycle, and any styling change republishes to
    /// re-render the View — each only on an actual change, not every ping (#41 PR3).
    private var appliedStyle: SpectrumStyle?
    /// Length of the track the bars distribute along, in points, as the View
    /// last reported it — the overlay width for vertical placements, the
    /// height for the horizontal `left`/`right` ones. The bar count is derived
    /// from it cava-style (fixed bar + gap, count fills the track), so it is 0
    /// until the View lays out.
    private var barTrackLength: Double = 0
    /// cava's autosens gain applied to the incoming magnitudes: raised
    /// ~0.1% per active frame, cut ~2% the moment any bar overshoots full
    /// height, so sustained peaks ride the top of the range. Kept across
    /// pauses, like cava.
    private var sens: Float = 1
    /// Fast extra ramp (~11%/frame) until the first overshoot calibrates
    /// the range.
    private var sensInit = true

    public init() {}

    public var isEnabled: Bool { interactor.spectrumStyle.enabled }
    public var style: SpectrumStyle { interactor.spectrumStyle }

    public func start() {
        // Subscribe once at startup — never rebuilt, so a config change cannot leak
        // duplicate subscriptions (#41 PR3). The interactor's capturing subject
        // persists across capture start/stop cycles, so a single sink stays valid.
        interactor.isCapturing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.capturing = value }
            .store(in: &cancellables)

        configInteractor.appStyleChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.applyStyle() }
            .store(in: &cancellables)

        applyStyle()
    }

    /// Idempotently reflects the live spectrum style. Called once at startup and
    /// for each `appStyleChanges` ping. Toggling `enabled` starts or stops the
    /// capture lifecycle so the spectrum appears/disappears without a restart
    /// (#41 PR3). Any other styling change (colors, placement, bar geometry, band
    /// settings) republishes via `objectWillChange` so `SpectrumView` — which
    /// snapshots `presenter.style` in its `body` — re-renders live; the bar
    /// *heights* are already read live each `tick()`, but the drawing style is
    /// not, so without this a styling-only edit kept the old look until an
    /// unrelated invalidation (#41 PR3 review, F2).
    private func applyStyle() {
        let style = interactor.spectrumStyle
        let previous = appliedStyle
        guard style != previous else { return }
        appliedStyle = style
        objectWillChange.send()

        guard previous?.enabled != style.enabled else { return }
        if style.enabled {
            interactor.start()
        } else if previous?.enabled == true {
            // Only tear down a capture that was actually running; the bars then
            // fall away naturally over the following ticks.
            interactor.stop()
            capturing = false
        }
    }

    public func stop() {
        cancellables.removeAll()
        interactor.stop()
        capturing = false
    }

    /// The View reports the length of the bar track (overlay width for
    /// vertical placements, height for horizontal) so the bar count can be
    /// derived cava-style (fixed bar + gap, the count fills the track).
    public func updateBarTrackLength(_ length: Double) {
        barTrackLength = length
    }

    /// DisplayLink frame tick: advances every bar one filter step toward the
    /// newest magnitudes and updates the animation flag. `frameInterval` is the
    /// display's seconds-per-frame (from `CADisplayLink`); cava's smoothing
    /// constants are derived from it so the fall speed and integral decay hold
    /// constant in wall-clock time across 60 Hz, 120 Hz ProMotion, and
    /// variable-refresh displays (#299). Defaults to 60 fps so unit tests and
    /// any timing-agnostic caller keep the historical behavior exactly.
    public func tick(frameInterval: Double = 1.0 / 60.0) {
        guard capturing || !motion.isEmpty else { return }
        let constants = spectrumFramerateConstants(frameInterval: frameInterval)
        let style = interactor.spectrumStyle
        let barCount = targetBarCount(style: style)
        let fresh = capturing ? interactor.magnitudes(barCount: barCount) : []
        let reduction = min(max(Float(style.noiseReduction), 0), 0.97)
        // Precomputed once per tick, not per bar (up to `maxBars` bars share
        // the same `reduction`/`constants`): `pow` is a real per-frame cost,
        // and `integralInputScale` makes a SUSTAINED signal's steady state
        // wall-clock invariant too, not just the decay-only case (#306 PR
        // review) — a constant `value` added every tick would otherwise
        // overshoot more at higher fps even with the decay term already exact.
        let integralDecay = pow(reduction, constants.integralExponent)
        let integralInputScale = (1 - integralDecay) / (1 - reduction)
        motion = (0..<barCount).map { bar in
            stepped(
                bar < motion.count ? motion[bar] : BarMotion(),
                target: (bar < fresh.count ? fresh[bar] : 0) * sens,
                reduction: reduction, constants: constants,
                integralDecay: integralDecay, integralInputScale: integralInputScale
            )
        }
        adjustSens(silence: fresh.allSatisfy { $0 == 0 }, framerateMod: constants.framerateMod)
        let animating =
            capturing
            || motion.contains {
                $0.mem > Self.silenceThreshold || $0.prev > Self.silenceThreshold
            }
        // Once the falloff finishes, drop the state entirely so idle ticks
        // can bail out on the guard above without per-frame array work.
        if !animating { motion = [] }
        setAnimating(animating)
    }

    /// Bar heights (0…1) for the current frame. Read-only — safe to call from
    /// inside a Canvas draw closure.
    public func binHeights() -> [Float] { motion.map { min($0.mem, 1) } }

    /// cava's bar count: as many fixed-thickness bars (plus gaps) as fit the
    /// reported track length, so bars keep the same thickness at any window
    /// size. Stereo rounds down to even so the two channels split it exactly.
    /// Capped so a tiny `bar_width` can't ask for more bars than the FFT
    /// resolves or than is worth drawing.
    private func targetBarCount(style: SpectrumStyle) -> Int {
        let slot = style.barWidth + style.barSpacing
        guard barTrackLength > 0, slot > 0 else { return 0 }
        let fit = min(Int((barTrackLength + style.barSpacing) / slot), Self.maxBars)
        return style.stereo ? fit / 2 * 2 : max(fit, 0)
    }

    /// Upper bound on the derived bar count (both a draw-cost guard and a
    /// ceiling near the FFT's usable bin count).
    private static let maxBars = 512

    /// Bars below this are treated as fully fallen (~1/4 pixel at 256 pt).
    private static let silenceThreshold: Float = 0.001
    /// cava's per-frame gravity-ramp increment (frame-count based, so the
    /// framerate compensation rides in `gravityScale`, not here).
    private static let fallIncrement: Float = 0.028

    /// One step of cava's bar filter. Attack adopts a louder input
    /// immediately as the new peak; a quieter one falls from its peak with
    /// accelerating speed (gravity release; skipped at noise_reduction
    /// ≤ 0.1, cava's passthrough mode) — near-still right after the peak so
    /// it stays readable, then briskly down to zero. The leaky integral
    /// then stacks the frame's value on the decayed memory: sustained
    /// energy compounds toward 1/(1-reduction) of its single-frame height
    /// while one-frame spikes stay small — the beat-favoring dynamics the
    /// autosens then pins to full scale.
    private func stepped(
        _ m: BarMotion, target: Float, reduction: Float, constants: SpectrumFramerateConstants,
        integralDecay: Float, integralInputScale: Float
    ) -> BarMotion {
        let (value, peak, fall): (Float, Float, Float) =
            target < m.prev && reduction > 0.1
            ? (
                max(m.peak * (1 - m.fall * m.fall * constants.gravityScale / reduction), 0),
                m.peak, m.fall + Self.fallIncrement
            )
            : (target, target, 0)
        return BarMotion(
            mem: m.mem * integralDecay + value * integralInputScale,
            prev: value, peak: peak, fall: fall)
    }

    /// cava's autosens feedback: any overshoot cuts the gain and ends the
    /// initial ramp; otherwise every non-silent frame raises it slightly.
    /// Silence freezes the gain so pauses can't wind it up. The per-frame
    /// steps scale with `framerateMod` so the gain settles at the same rate
    /// in wall-clock time regardless of refresh rate.
    private func adjustSens(silence: Bool, framerateMod: Float) {
        let overshoot = motion.contains { $0.mem > 1 }
        sens *= sensFactor(overshoot: overshoot, silence: silence, framerateMod: framerateMod)
        sensInit = sensInit && !overshoot
    }

    private func sensFactor(overshoot: Bool, silence: Bool, framerateMod: Float) -> Float {
        guard !overshoot else { return 1 - 0.02 * framerateMod }
        guard !silence else { return 1 }
        return (1 + 0.001 * framerateMod)
            * (sensInit ? 1 + 0.1 * framerateMod : 1)
    }

    private func setAnimating(_ value: Bool) {
        guard isAnimating != value else { return }
        isAnimating = value
    }
}

/// cava's framerate-compensation constants for a display frame interval (#299).
/// cavacore tunes its filter at a 66 fps reference (`framerate_mod = 66 / fps`)
/// and derives the integral-decay and gravity scales from it; the old fixed
/// 60 fps assumption made the bars fall at double speed on 120 Hz ProMotion.
/// Deriving `fps` from the real per-frame interval keeps the fall speed and
/// decay constant in wall-clock time regardless of refresh rate.
struct SpectrumFramerateConstants: Equatable {
    /// cava's `framerate_mod` = 66 / fps (1.1 at 60 fps, 0.55 at 120 fps).
    let framerateMod: Float
    /// Leaky-integral per-frame decay exponent, `60 / fps` — applied once
    /// per frame as `reduction ^ integralExponent`. Compounding that
    /// per-frame factor over one second (`fps` frames) reproduces
    /// `reduction ^ 60` exactly, i.e. `(reduction ^ integralExponent) ^ fps
    /// == reduction ^ 60` for any fps — so the per-second decay rate is
    /// exactly invariant across frame rates, unlike cava's own
    /// `framerate_mod ^ 0.1` approximation (#306: that curve
    /// under-compensates, so the integral — lyra's own addition on top of
    /// cavacore — drained visibly faster in wall-clock time at 120 Hz than
    /// at 60 Hz). 60, not 66, is the reference so `fps == 60` reduces to
    /// exponent `1` — the exact pre-#299 hardcoded-60fps decay (`reduction`,
    /// no divisor at all).
    let integralExponent: Float
    /// Gravity-release scale, `framerateMod ^ 2.5 * 2`.
    let gravityScale: Float
}

/// The `SpectrumFramerateConstants` for a display's seconds-per-frame. A
/// non-finite interval (NaN / infinite frame timestamp) can't be clamped —
/// `min`/`max` propagate NaN — so it falls back to the 60 fps reference. A
/// finite interval (including a zero or negative one from a hitched frame) is
/// clamped to 24…240 fps so it can't blow up the constants.
func spectrumFramerateConstants(frameInterval: Double) -> SpectrumFramerateConstants {
    let hz = frameInterval.isFinite ? 1 / max(frameInterval, .leastNormalMagnitude) : 60
    let fps = min(max(hz, 24), 240)
    let mod = Float(66 / fps)
    return SpectrumFramerateConstants(
        framerateMod: mod, integralExponent: Float(60 / fps), gravityScale: pow(mod, 2.5) * 2)
}
