import Domain
import Foundation
import Testing

@testable import Presenters

@Suite("CharacterPool")
struct CharacterPoolTests {
    @Test("latin charset produces non-empty pool")
    func latinCharset() {
        let pool = CharacterPool(charsets: [.latin])
        let result = pool.random(count: 10)
        #expect(result.count == 10)
    }

    @Test("cyrillic charset produces non-empty pool")
    func cyrillicCharset() {
        let pool = CharacterPool(charsets: [.cyrillic])
        #expect(pool.random(count: 5).count == 5)
    }

    @Test("greek charset produces non-empty pool")
    func greekCharset() {
        let pool = CharacterPool(charsets: [.greek])
        #expect(pool.random(count: 5).count == 5)
    }

    @Test("symbols charset produces non-empty pool")
    func symbolsCharset() {
        let pool = CharacterPool(charsets: [.symbols])
        #expect(pool.random(count: 5).count == 5)
    }

    @Test("cjk charset produces non-empty pool")
    func cjkCharset() {
        let pool = CharacterPool(charsets: [.cjk])
        #expect(pool.random(count: 5).count == 5)
    }

    @Test("multiple charsets combined")
    func multipleCharsets() {
        let pool = CharacterPool(charsets: [.latin, .greek, .symbols])
        #expect(pool.random(count: 20).count == 20)
    }

    @Test("empty charsets fallback to ?")
    func emptyCharsets() {
        let pool = CharacterPool(charsets: [])
        let ch = pool.random
        #expect(ch == "?")
    }
}

@Suite("DecodeEffectState")
struct DecodeEffectStateTests {
    @MainActor
    @Test("set updates displayText immediately")
    func setUpdatesDisplay() {
        let state = DecodeEffectState(config: DecodeEffect(duration: 0))
        state.set("Hello")
        #expect(state.displayText == "Hello")
        #expect(state.isAnimating == false)
    }

    @MainActor
    @Test("decode with empty text completes immediately")
    func decodeEmptyText() {
        let state = DecodeEffectState(config: DecodeEffect(duration: 0))
        var completed = false
        state.decode(to: "") { completed = true }
        #expect(completed)
        #expect(state.displayText == "")
        #expect(state.isAnimating == false)
    }

    @MainActor
    @Test("stop cancels animation")
    func stopCancels() {
        let state = DecodeEffectState(config: DecodeEffect(duration: 1.0))
        state.startLoading()
        #expect(state.isAnimating == true)
        state.stop()
        #expect(state.isAnimating == false)
    }

    @MainActor
    @Test("startLoading sets isAnimating and displayText")
    func startLoadingSetsState() {
        let state = DecodeEffectState(config: DecodeEffect(duration: 1.0, charsets: [.latin]))
        state.startLoading(placeholderLength: 8)
        #expect(state.isAnimating == true)
        #expect(state.displayText.count == 8)
    }

    @MainActor
    @Test("onUpdate callback is called on set")
    func onUpdateCallback() {
        let state = DecodeEffectState(config: DecodeEffect(duration: 0))
        var received: String?
        state.onUpdate = { received = $0 }
        state.set("Test")
        #expect(received == "Test")
    }

    @MainActor
    @Test("decode with duration 0 completes via timer")
    func decodeWithZeroDuration() async {
        let state = DecodeEffectState(config: DecodeEffect(duration: 0, charsets: [.latin]))
        var completed = false
        state.decode(to: "AB") { completed = true }

        // Timer-based, wait for RunLoop
        let deadline = ContinuousClock.now + .seconds(2)
        while !completed, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(completed)
        #expect(state.displayText == "AB")
    }

    @MainActor
    @Test("startLoading uses default placeholder length of 12")
    func startLoadingDefaultLength() {
        let state = DecodeEffectState(config: DecodeEffect(duration: 1.0, charsets: [.latin]))
        state.startLoading()
        #expect(state.isAnimating)
        #expect(state.displayText.count == 12)
        state.stop()
    }

    @MainActor
    @Test("startLoading timer randomizes display text on tick")
    func startLoadingTicksRandomize() async {
        let state = DecodeEffectState(config: DecodeEffect(duration: 1.0, charsets: [.latin]))
        state.startLoading(placeholderLength: 6)
        let initial = state.displayText

        // Wait for at least one timer tick (interval: 0.05s)
        let deadline = ContinuousClock.now + .seconds(2)
        while state.displayText == initial, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }

        // Display text should have changed due to tickLoading
        #expect(state.displayText.count == 6)
        #expect(state.displayText != initial, "timer should have randomized display text")
        state.stop()
    }

    @MainActor
    @Test("decode with non-zero duration animates then completes")
    func decodeWithNonZeroDuration() async {
        let state = DecodeEffectState(config: DecodeEffect(duration: 0.1, charsets: [.latin]))
        var completed = false
        state.decode(to: "Test") { completed = true }

        #expect(state.isAnimating)

        let deadline = ContinuousClock.now + .seconds(3)
        while !completed, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(30))
        }

        #expect(completed)
        #expect(state.displayText == "Test")
        #expect(!state.isAnimating)
    }
}
