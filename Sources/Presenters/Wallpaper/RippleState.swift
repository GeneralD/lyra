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
        pruneExpired()
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
        pruneExpired()
    }

    /// Drops ripples past their visible window and reports whether any remain
    /// alive. Mutating on purpose: pruning drains `ripples` to empty once the
    /// last ripple expires, so the *next* call short-circuits on the
    /// `ripples.isEmpty` guard without ever reading the clock. The
    /// DisplayLink-driven liveness check runs every frame, but `cleanup` used to
    /// fire only when a new ripple was appended — so an idle layer (e.g. the
    /// pointer left the screen, no new ripples spawning) kept stale ripples
    /// around and read the clock forever. Folding the prune into the liveness
    /// check keeps the layer free of a dependency access at rest (#258).
    public func pruneAndCheckLiveness() -> Bool {
        guard rippleConfig.enabled, !ripples.isEmpty else { return false }
        pruneExpired()
        return !ripples.isEmpty
    }

    private func visibleWindow(for ripple: Ripple) -> TimeInterval {
        ripple.idle ? rippleConfig.duration * 3 : rippleConfig.duration
    }

    private func pruneExpired() {
        let now = date.now
        ripples.removeAll { now.timeIntervalSince($0.startTime) >= visibleWindow(for: $0) }
    }
}
