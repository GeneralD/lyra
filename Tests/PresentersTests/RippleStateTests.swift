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
}
