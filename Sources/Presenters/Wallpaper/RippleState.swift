import Dependencies
import Domain
import Foundation
import Observation

@MainActor @Observable
public final class RippleState {
    public struct Ripple: Identifiable {
        public let id = UUID()
        public let position: CGPoint
        public let startTime: Date
        public let idle: Bool
        public let hueShift: Double = .random(in: -0.15...0.15)
    }

    @ObservationIgnored
    @Dependency(\.date) private var date

    public var ripples: [Ripple] = []
    private var currentPosition: CGPoint = .zero
    private var lastRipplePosition: CGPoint = .zero
    private var lastIdleRipple: Date?
    private let rippleConfig: RippleStyle

    public init(config: RippleStyle = .init()) {
        rippleConfig = config
    }

    public func update(screenPoint: CGPoint) {
        guard rippleConfig.enabled else { return }
        currentPosition = screenPoint
        let distance = hypot(screenPoint.x - lastRipplePosition.x, screenPoint.y - lastRipplePosition.y)
        guard distance > 40 else { return }
        let now = date.now
        lastRipplePosition = screenPoint
        lastIdleRipple = now
        ripples.append(.init(position: screenPoint, startTime: now, idle: false))
        cleanup()
    }

    public func idle() {
        guard rippleConfig.enabled, rippleConfig.idle > 0 else { return }
        let now = date.now
        guard let last = lastIdleRipple else {
            lastIdleRipple = now
            return
        }
        guard now.timeIntervalSince(last) > rippleConfig.idle else { return }
        lastIdleRipple = now
        ripples.append(.init(position: currentPosition, startTime: now, idle: true))
        cleanup()
    }

    /// True while at least one ripple is still within its visible animation
    /// window. Guarded so the clock is never read when ripples are disabled or
    /// none are alive, keeping the DisplayLink-driven liveness check free of a
    /// dependency access at rest (#258).
    public var hasLiveRipples: Bool {
        guard rippleConfig.enabled, !ripples.isEmpty else { return false }
        let now = date.now
        return ripples.contains { now.timeIntervalSince($0.startTime) < visibleWindow(for: $0) }
    }

    private func visibleWindow(for ripple: Ripple) -> TimeInterval {
        ripple.idle ? rippleConfig.duration * 3 : rippleConfig.duration
    }

    private func cleanup() {
        let now = date.now
        ripples.removeAll { now.timeIntervalSince($0.startTime) >= visibleWindow(for: $0) }
    }
}
