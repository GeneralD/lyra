import AppKit
import Combine
import CoreFoundation
import Dependencies
import Domain
import Foundation

@MainActor
public final class RipplePresenter: ObservableObject {
    public private(set) var rippleState: RippleState?
    public var screenOrigin: CGPoint { screenRect.origin }
    private var screenRect: CGRect
    private var mouseInScreen = false
    private var mouseMonitor: Any?
    /// `CACurrentMediaTime()` of the last processed mouse-move event, used to
    /// throttle ripple work to roughly 30 Hz during rapid motion (#271).
    private var lastMouseMoveTime: CFTimeInterval = 0
    /// The ripple config last applied by `applyStyle()`, used to diff against a
    /// hot-reload ping so the monitor and `RippleState` are only reworked on a
    /// meaningful change (#41 PR3).
    private var appliedRipple: RippleStyle?
    private var cancellables: Set<AnyCancellable> = []

    @Dependency(\.wallpaperInteractor) private var interactor
    @Dependency(\.configInteractor) private var configInteractor

    /// Drives whether `RippleView` keeps its per-frame `TimelineView` running.
    /// Stays `false` while no ripple is alive so an enabled-but-idle ripple
    /// layer does not redraw the Canvas every frame (#258).
    @Published public private(set) var isAnimating = false

    public init(screenRect: CGRect = .zero) {
        self.screenRect = screenRect
    }

    public var isEnabled: Bool { interactor.rippleConfig.enabled }
    public var rippleConfig: RippleStyle { interactor.rippleConfig }

    // MARK: - Mouse handling

    public func handleMouseLocation(_ point: CGPoint) {
        guard screenRect.width > 0, screenRect.height > 0, screenRect.contains(point) else {
            mouseInScreen = false
            return
        }
        mouseInScreen = true
        rippleState?.update(screenPoint: point)
        setAnimating(rippleState?.pruneAndCheckLiveness() ?? false)
    }

    public func updateScreenRect(_ rect: CGRect) {
        screenRect = rect
    }

    // MARK: - Ripple drawing data

    public struct RippleDrawingContext {
        public let rect: CGRect
        public let color: ColorConfig
        public let shape: RippleShape
    }

    /// Computes draw commands for all visible ripples.
    public func drawingContexts(canvasSize: CGSize, now: Date) -> [RippleDrawingContext] {
        guard let rippleState else { return [] }
        let config = rippleConfig
        let baseHSB: (hue: Double, saturation: Double, brightness: Double) =
            switch config.color {
            case .solid(let c): c.hsb
            case .gradient(let cs): (cs.first ?? .white).hsb
            }
        return rippleState.ripples.compactMap { ripple -> RippleDrawingContext? in
            let elapsed = now.timeIntervalSince(ripple.startTime)
            let dur = ripple.idle ? config.duration * 3 : config.duration
            guard elapsed < dur else { return nil }
            let t = elapsed / dur
            let easeOut = 1 - (1 - t) * (1 - t)
            let radius = easeOut * config.radius
            let x = ripple.position.x - screenOrigin.x
            let y = canvasSize.height - (ripple.position.y - screenOrigin.y)
            return RippleDrawingContext(
                rect: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2),
                color: ColorConfig(
                    hue: (baseHSB.hue + ripple.hueShift).truncatingRemainder(dividingBy: 1), saturation: baseHSB.saturation,
                    brightness: baseHSB.brightness, alpha: pow(1 - t, 0.6)),
                shape: config.shape
            )
        }
    }

    public func start() {
        applyStyle()

        // Subscribe once at startup. Each config change emits a Void ping and calls
        // applyStyle() without ever replacing this subscription (#41 PR3).
        configInteractor.appStyleChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.applyStyle() }
            .store(in: &cancellables)
    }

    /// Idempotently reflects the live ripple config. Called once at startup and for
    /// each `appStyleChanges` ping. `RippleState` freezes enabled/idle/duration at
    /// construction, so it is rebuilt only when one of those changes — never on an
    /// unrelated edit, which would wipe live ripples (color/radius/shape are read
    /// live in `drawingContexts`). The global mouse monitor is attached/detached
    /// only when `enabled` flips, so a disabled ripple installs none and a re-enable
    /// never double-registers.
    private func applyStyle() {
        let config = interactor.rippleConfig
        let previous = appliedRipple
        appliedRipple = config

        let framesDiffer =
            previous == nil
            || previous!.enabled != config.enabled
            || previous!.idle != config.idle
            || previous!.duration != config.duration
        if framesDiffer {
            rippleState = RippleState(config: config)
        }

        guard previous?.enabled != config.enabled else { return }
        if config.enabled {
            attachMouseMonitor()
        } else {
            detachMouseMonitor()
            setAnimating(false)
        }
    }

    private func attachMouseMonitor() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.handleGlobalMouseMove()
        }
    }

    private func detachMouseMonitor() {
        mouseMonitor.map(NSEvent.removeMonitor)
        mouseMonitor = nil
    }

    /// Bridges a global mouse-move callback onto the MainActor and forwards it
    /// to the throttled handler. Global-monitor callbacks are delivered on the
    /// main thread, so `assumeIsolated` runs synchronously instead of hopping
    /// through a `Task` per event; off-screen and throttled samples bail out
    /// inside `processMouseMove` without further work, capping per-event cost
    /// during rapid motion (#271). Split out from the monitor closure so the
    /// main-actor hop is unit-testable — the global monitor itself cannot be
    /// fired from a test.
    nonisolated func handleGlobalMouseMove() {
        MainActor.assumeIsolated { processMouseMove() }
    }

    /// Applies the screen-exclusion filter and the ~30 Hz throttle to one
    /// mouse-move sample before forwarding it to `handleMouseLocation` (#271).
    /// The defaults read the live cursor/clock for the global monitor; tests
    /// inject deterministic values, since real samples cannot be simulated.
    func processMouseMove(at location: CGPoint = NSEvent.mouseLocation, time: CFTimeInterval = CACurrentMediaTime()) {
        // Movement outside the overlay screen never spawns a ripple — reset the
        // hover flag and bail before touching ripple state.
        guard screenRect.contains(location) else {
            mouseInScreen = false
            return
        }
        // Cap ripple processing to ~30 Hz so rapid in-screen motion does not
        // redraw the ripple layer on every event.
        guard time - lastMouseMoveTime >= 0.033 else { return }
        lastMouseMoveTime = time
        handleMouseLocation(location)
    }

    public func stop() {
        cancellables.removeAll()
        detachMouseMonitor()
    }

    /// Called from DisplayLink at frame rate. The handler is always installed now
    /// (#41 PR3), so a disabled ripple bails on the first guard and pays no
    /// per-frame cost — enabling it at runtime resumes idle spawning immediately.
    public func idle() {
        guard isEnabled else { return }
        spawnIdleRippleWhileHovering()
        setAnimating(rippleState?.pruneAndCheckLiveness() ?? false)
    }

    private func spawnIdleRippleWhileHovering() {
        guard mouseInScreen else { return }
        rippleState?.idle()
    }

    private func setAnimating(_ value: Bool) {
        guard isAnimating != value else { return }
        isAnimating = value
    }
}
