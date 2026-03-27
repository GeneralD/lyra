import AppKit
import Dependencies
import Domain
import Foundation

@MainActor
public final class RipplePresenter: ObservableObject {
    public private(set) var rippleState: RippleState?
    public let screenOrigin: CGPoint
    private var mouseMonitor: Any?

    @Dependency(\.wallpaperInteractor) private var interactor

    public init(screenOrigin: CGPoint = .zero) {
        self.screenOrigin = screenOrigin
    }

    public var isEnabled: Bool { interactor.rippleConfig.enabled }
    public var rippleConfig: RippleStyle { interactor.rippleConfig }

    // MARK: - Ripple drawing data

    public struct RippleDrawingContext {
        public let rect: CGRect
        public let color: ColorConfig
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
                    brightness: baseHSB.brightness, alpha: pow(1 - t, 0.6))
            )
        }
    }

    public func start() {
        let config = interactor.rippleConfig
        rippleState = RippleState(config: config)

        guard config.enabled else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            Task { @MainActor in
                self?.rippleState?.update(screenPoint: NSEvent.mouseLocation)
            }
        }
    }

    public func stop() {
        mouseMonitor.map(NSEvent.removeMonitor)
        mouseMonitor = nil
    }

    /// Called from DisplayLink at frame rate.
    public func idle() {
        rippleState?.idle()
    }
}
