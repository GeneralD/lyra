import Domain
import Foundation
import Testing

@testable import Presenters

@Suite("RippleState")
struct RippleStateTests {

    @MainActor
    @Test("update adds ripple when distance exceeds threshold")
    func updateAddsRipple() {
        let state = RippleState(config: RippleStyle(enabled: true))
        state.update(screenPoint: CGPoint(x: 0, y: 0))
        state.update(screenPoint: CGPoint(x: 100, y: 100))
        #expect(state.ripples.count >= 1)
    }

    @MainActor
    @Test("update does not add ripple when distance is below threshold")
    func updateBelowThreshold() {
        let state = RippleState(config: RippleStyle(enabled: true))
        state.update(screenPoint: CGPoint(x: 0, y: 0))
        let countAfterFirst = state.ripples.count
        state.update(screenPoint: CGPoint(x: 5, y: 5))
        #expect(state.ripples.count == countAfterFirst)
    }

    @MainActor
    @Test("update does nothing when disabled")
    func updateDisabled() {
        let state = RippleState(config: RippleStyle(enabled: false))
        state.update(screenPoint: CGPoint(x: 0, y: 0))
        state.update(screenPoint: CGPoint(x: 100, y: 100))
        #expect(state.ripples.isEmpty)
    }

    @MainActor
    @Test("idle does nothing when disabled")
    func idleDisabled() {
        let state = RippleState(config: RippleStyle(enabled: false))
        state.idle()
        #expect(state.ripples.isEmpty)
    }

    @MainActor
    @Test("idle does nothing when idle interval is 0")
    func idleZeroInterval() {
        let state = RippleState(config: RippleStyle(enabled: true, idle: 0))
        state.idle()
        #expect(state.ripples.isEmpty)
    }

    @MainActor
    @Test("idle adds ripple when interval elapsed")
    func idleAddsRipple() async throws {
        // Use a very short idle interval so the condition is met quickly
        let state = RippleState(config: RippleStyle(enabled: true, idle: 0.01))

        // Wait for the idle interval to elapse
        let deadline = ContinuousClock.now + .seconds(2)
        while state.ripples.isEmpty, ContinuousClock.now < deadline {
            state.idle()
            try? await Task.sleep(for: .milliseconds(20))
        }

        #expect(!state.ripples.isEmpty, "idle should add a ripple after interval elapses")
        #expect(state.ripples.first?.idle == true, "ripple should be marked as idle")
    }

    @MainActor
    @Test("cleanup removes expired ripples")
    func cleanupRemovesExpired() async throws {
        // Use a very short duration so ripples expire quickly
        let state = RippleState(config: RippleStyle(enabled: true, duration: 0.01))
        state.update(screenPoint: CGPoint(x: 0, y: 0))
        state.update(screenPoint: CGPoint(x: 100, y: 100))
        #expect(!state.ripples.isEmpty)

        // Wait for ripples to expire (duration * 3 = 0.03s)
        try await Task.sleep(for: .milliseconds(100))

        // Trigger another update to run cleanup
        state.update(screenPoint: CGPoint(x: 200, y: 200))
        state.update(screenPoint: CGPoint(x: 300, y: 300))

        // Original ripples should have been cleaned up; only new ones remain
        let countAfterCleanup = state.ripples.count
        #expect(countAfterCleanup <= 2, "expired ripples should have been removed during cleanup")
    }
}
