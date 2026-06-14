import AppKit
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

    @Dependency(\.wallpaperInteractor) private var interactor

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
        let config = interactor.rippleConfig
        rippleState = RippleState(config: config)

        guard config.enabled else { return }
        // Global mouse-monitor callbacks are delivered on the main thread, so we
        // run synchronously via `assumeIsolated` instead of hopping through a
        // `Task` per event. Off-screen and throttled events bail out inside
        // `processMouseMove` without further work, capping per-event cost during
        // rapid mouse motion (#271).
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            MainActor.assumeIsolated { self?.processMouseMove() }
        }
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
        mouseMonitor.map(NSEvent.removeMonitor)
        mouseMonitor = nil
    }

    /// Called from DisplayLink at frame rate.
    public func idle() {
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
