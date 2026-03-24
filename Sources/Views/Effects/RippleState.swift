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

    public var ripples: [Ripple] = []
    private var currentPosition: CGPoint = .zero
    private var lastRipplePosition: CGPoint = .zero
    private var lastIdleRipple: Date = .now

    @ObservationIgnored
    @Dependency(\.appStyle) private var config

    public init() {}

    public func update(screenPoint: CGPoint) {
        guard config.ripple.enabled else { return }
        currentPosition = screenPoint
        let distance = hypot(screenPoint.x - lastRipplePosition.x, screenPoint.y - lastRipplePosition.y)
        guard distance > 40 else { return }
        lastRipplePosition = screenPoint
        lastIdleRipple = .now
        ripples.append(.init(position: screenPoint, startTime: .now, idle: false))
        cleanup()
    }

    public func idle() {
        guard config.ripple.enabled,
            config.ripple.idle > 0,
            Date.now.timeIntervalSince(lastIdleRipple) > config.ripple.idle
        else { return }
        lastIdleRipple = .now
        ripples.append(.init(position: currentPosition, startTime: .now, idle: true))
        cleanup()
    }

    private func cleanup() {
        ripples.removeAll { Date.now.timeIntervalSince($0.startTime) > config.ripple.duration * 3 }
    }
}
