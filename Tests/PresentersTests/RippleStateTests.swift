import Dependencies
import Domain
import Foundation
import Testing

@testable import Presenters

// MARK: - Test helper

/// Mutable date source for deterministic time advancement in tests.
private final class MutableClock: @unchecked Sendable {
    var now: Date
    init(_ initial: Date = Date(timeIntervalSinceReferenceDate: 0)) {
        now = initial
    }
    func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}

@Suite("RippleState")
struct RippleStateTests {

    @MainActor
    @Test("update adds ripple when distance exceeds threshold")
    func updateAddsRipple() {
        let clock = MutableClock()
        withDependencies {
            $0.date = .init { clock.now }
        } operation: {
            let state = RippleState(config: RippleStyle(enabled: true))
            state.update(screenPoint: CGPoint(x: 0, y: 0))
            state.update(screenPoint: CGPoint(x: 100, y: 100))
            #expect(state.ripples.count >= 1)
        }
    }

    @MainActor
    @Test("update does not add ripple when distance is below threshold")
    func updateBelowThreshold() {
        let clock = MutableClock()
        withDependencies {
            $0.date = .init { clock.now }
        } operation: {
            let state = RippleState(config: RippleStyle(enabled: true))
            state.update(screenPoint: CGPoint(x: 0, y: 0))
            let countAfterFirst = state.ripples.count
            state.update(screenPoint: CGPoint(x: 5, y: 5))
            #expect(state.ripples.count == countAfterFirst)
        }
    }

    @MainActor
    @Test("update does nothing when disabled")
    func updateDisabled() {
        let clock = MutableClock()
        withDependencies {
            $0.date = .init { clock.now }
        } operation: {
            let state = RippleState(config: RippleStyle(enabled: false))
            state.update(screenPoint: CGPoint(x: 0, y: 0))
            state.update(screenPoint: CGPoint(x: 100, y: 100))
            #expect(state.ripples.isEmpty)
        }
    }

    @MainActor
    @Test("idle does nothing when disabled")
    func idleDisabled() {
        let clock = MutableClock()
        withDependencies {
            $0.date = .init { clock.now }
        } operation: {
            let state = RippleState(config: RippleStyle(enabled: false))
            state.idle()
            #expect(state.ripples.isEmpty)
        }
    }

    @MainActor
    @Test("idle does nothing when idle interval is 0")
    func idleZeroInterval() {
        let clock = MutableClock()
        withDependencies {
            $0.date = .init { clock.now }
        } operation: {
            let state = RippleState(config: RippleStyle(enabled: true, idle: 0))
            state.idle()
            #expect(state.ripples.isEmpty)
        }
    }

    @MainActor
    @Test("idle adds ripple when interval elapsed")
    func idleAddsRipple() {
        let clock = MutableClock()
        withDependencies {
            $0.date = .init { clock.now }
        } operation: {
            let state = RippleState(config: RippleStyle(enabled: true, idle: 0.01))
            // Below threshold — no ripple
            clock.advance(by: 0.005)
            state.idle()
            #expect(state.ripples.isEmpty)

            // Above threshold — fires
            clock.advance(by: 0.02)
            state.idle()
            #expect(state.ripples.count == 1)
            #expect(state.ripples.first?.idle == true)
        }
    }

    @MainActor
    @Test("cleanup removes pointer ripples at their visible window")
    func cleanupRemovesExpiredPointerRipples() {
        let clock = MutableClock()
        withDependencies {
            $0.date = .init { clock.now }
        } operation: {
            let state = RippleState(config: RippleStyle(enabled: true, duration: 0.01))
            state.update(screenPoint: CGPoint(x: 0, y: 0))
            state.update(screenPoint: CGPoint(x: 100, y: 100))
            #expect(state.ripples.count == 1)

            // Older than duration, but still younger than duration * 3.
            clock.advance(by: 0.02)

            // Trigger cleanup via another update
            state.update(screenPoint: CGPoint(x: 200, y: 200))

            #expect(
                state.ripples.count == 1,
                "pointer ripples should not stay until the idle-ripple window"
            )
            #expect(state.ripples.first?.position == CGPoint(x: 200, y: 200))
        }
    }

    @MainActor
    @Test("pruneAndCheckLiveness drains the array once every ripple expires, without a new spawn")
    func pruneAndCheckLivenessDrainsWithoutSpawn() {
        let clock = MutableClock()
        withDependencies {
            $0.date = .init { clock.now }
        } operation: {
            let state = RippleState(config: RippleStyle(enabled: true, duration: 0.01))
            state.update(screenPoint: CGPoint(x: 0, y: 0))
            state.update(screenPoint: CGPoint(x: 100, y: 100))
            #expect(state.pruneAndCheckLiveness())

            // Age every ripple out of its window, then prune again *without*
            // appending a new ripple — this is the pointer-left-screen path
            // where `update`/`idle` never fire. The array must drain so a
            // subsequent call short-circuits on the empty guard (#258).
            clock.advance(by: 0.05)
            #expect(!state.pruneAndCheckLiveness())
            #expect(state.ripples.isEmpty)
        }
    }
}
