import Dependencies
import Domain
import Foundation
import Testing

@testable import Presenters

@Suite("CharacterPool")
struct CharacterPoolTests {
    @Test("latin charset produces non-empty pool")
    func latinCharset() {
        let pool = CharacterPool(charsets: [.latin])
        #expect(pool.count > 0)
    }

    @Test("cyrillic charset produces non-empty pool")
    func cyrillicCharset() {
        #expect(CharacterPool(charsets: [.cyrillic]).count > 0)
    }

    @Test("greek charset produces non-empty pool")
    func greekCharset() {
        #expect(CharacterPool(charsets: [.greek]).count > 0)
    }

    @Test("symbols charset produces non-empty pool")
    func symbolsCharset() {
        #expect(CharacterPool(charsets: [.symbols]).count > 0)
    }

    @Test("cjk charset produces non-empty pool")
    func cjkCharset() {
        #expect(CharacterPool(charsets: [.cjk]).count > 0)
    }

    @Test("multiple charsets combined")
    func multipleCharsets() {
        let pool = CharacterPool(charsets: [.latin, .greek, .symbols])
        let latin = CharacterPool(charsets: [.latin]).count
        #expect(pool.count > latin)
    }

    @Test("empty charsets produce empty pool")
    func emptyCharsets() {
        #expect(CharacterPool(charsets: []).count == 0)
    }

    @Test("character(at:) returns character at index")
    func characterAt() {
        let pool = CharacterPool(charsets: [.latin])
        #expect(pool.character(at: 0) == pool.characters[0])
    }
}

// Sequence-based fake so tick tests see varying output.
private struct SequenceRandomSource: RandomSource {
    let values: [Int]
    let counter: Counter = Counter()
    func next(below count: Int) -> Int {
        let v = counter.next()
        return values[v % values.count] % count
    }
    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func next() -> Int {
            lock.lock()
            defer { lock.unlock() }
            let v = value
            value += 1
            return v
        }
    }
}

@Suite("DecodeEffectState")
struct DecodeEffectStateTests {
    @MainActor
    @Test("set updates displayText immediately")
    func setUpdatesDisplay() {
        withDependencies {
            $0.continuousClock = ImmediateClock()
        } operation: {
            let state = DecodeEffectState(config: DecodeEffect(duration: 0))
            state.set("Hello")
            #expect(state.displayText == "Hello")
            #expect(!state.isAnimating)
        }
    }

    @MainActor
    @Test("decode with empty text completes immediately")
    func decodeEmptyText() {
        withDependencies {
            $0.continuousClock = ImmediateClock()
        } operation: {
            let state = DecodeEffectState(config: DecodeEffect(duration: 0))
            var completed = false
            state.decode(to: "") { completed = true }
            #expect(completed)
            #expect(state.displayText == "")
            #expect(!state.isAnimating)
        }
    }

    @MainActor
    @Test("stop cancels animation")
    func stopCancels() {
        withDependencies {
            $0.continuousClock = ImmediateClock()
        } operation: {
            let state = DecodeEffectState(config: DecodeEffect(duration: 1.0))
            state.startLoading()
            #expect(state.isAnimating)
            state.stop()
            #expect(!state.isAnimating)
        }
    }

    @MainActor
    @Test("startLoading sets isAnimating and displayText")
    func startLoadingSetsState() {
        withDependencies {
            $0.continuousClock = ImmediateClock()
        } operation: {
            let state = DecodeEffectState(config: DecodeEffect(duration: 1.0, charsets: [.latin]))
            state.startLoading(placeholderLength: 8)
            #expect(state.isAnimating)
            #expect(state.displayText.count == 8)
            state.stop()
        }
    }

    @MainActor
    @Test("onUpdate callback is called on set")
    func onUpdateCallback() {
        withDependencies {
            $0.continuousClock = ImmediateClock()
        } operation: {
            let state = DecodeEffectState(config: DecodeEffect(duration: 0))
            var received: String?
            state.onUpdate = { received = $0 }
            state.set("Test")
            #expect(received == "Test")
        }
    }

    @MainActor
    @Test("decode with duration 0 completes immediately")
    func decodeWithZeroDuration() {
        withDependencies {
            $0.continuousClock = ImmediateClock()
        } operation: {
            let state = DecodeEffectState(config: DecodeEffect(duration: 0, charsets: [.latin]))
            var completed = false
            state.decode(to: "AB") { completed = true }
            #expect(completed)
            #expect(state.displayText == "AB")
        }
    }

    @MainActor
    @Test("startLoading uses default placeholder length of 12")
    func startLoadingDefaultLength() {
        withDependencies {
            $0.continuousClock = ImmediateClock()
        } operation: {
            let state = DecodeEffectState(config: DecodeEffect(duration: 1.0, charsets: [.latin]))
            state.startLoading()
            #expect(state.isAnimating)
            #expect(state.displayText.count == 12)
            state.stop()
        }
    }

    @MainActor
    @Test("startLoading timer randomizes display text on tick")
    func startLoadingTicksRandomize() async {
        let testClock = TestClock()
        await withDependencies {
            $0.continuousClock = testClock
            $0.randomSource = SequenceRandomSource(values: Array(0..<1000))
        } operation: {
            let state = DecodeEffectState(config: DecodeEffect(duration: 1.0, charsets: [.latin]))
            state.startLoading(placeholderLength: 6)
            let initial = state.displayText

            await Task.yield()
            await testClock.advance(by: .milliseconds(50))

            #expect(state.displayText.count == 6)
            #expect(state.displayText != initial, "timer should have randomized display text")
            state.stop()
        }
    }

    @MainActor
    @Test("decode with non-zero duration animates then completes")
    func decodeWithNonZeroDuration() async {
        await withDependencies {
            $0.continuousClock = ImmediateClock()
        } operation: {
            let state = DecodeEffectState(config: DecodeEffect(duration: 0.1, charsets: [.latin]))
            var completed = false
            state.decode(to: "Test") { completed = true }

            #expect(state.isAnimating)

            await state.task?.value

            #expect(completed)
            #expect(state.displayText == "Test")
            #expect(!state.isAnimating)
        }
    }

    @MainActor
    @Test("startLoading with empty charset fills with '?'")
    func startLoadingEmptyPool() {
        withDependencies {
            $0.continuousClock = ImmediateClock()
        } operation: {
            let state = DecodeEffectState(config: DecodeEffect(duration: 1.0, charsets: []))
            state.startLoading(placeholderLength: 5)
            #expect(state.displayText == "?????")
            state.stop()
        }
    }

    @MainActor
    @Test("decode with empty charset fills non-target slots with '?'")
    func decodeEmptyPool() {
        withDependencies {
            $0.continuousClock = TestClock()
            $0.randomSource = SequenceRandomSource(values: [0])
        } operation: {
            let state = DecodeEffectState(config: DecodeEffect(duration: 1.0, charsets: []))
            state.decode(to: "ABCD")
            #expect(state.displayText == "????")
            state.stop()
        }
    }

    @MainActor
    @Test("decode called while animating restarts cleanly")
    func decodeRestart() async {
        await withDependencies {
            $0.continuousClock = ImmediateClock()
            $0.randomSource = SequenceRandomSource(values: [0])
        } operation: {
            let state = DecodeEffectState(config: DecodeEffect(duration: 0.1, charsets: [.latin]))
            state.decode(to: "FIRST")
            #expect(state.isAnimating)

            state.decode(to: "SECOND")
            #expect(state.isAnimating)

            await state.task?.value
            #expect(state.displayText == "SECOND")
        }
    }

    @MainActor
    @Test("startLoading then decode transitions to decode target")
    func startLoadingThenDecode() async {
        await withDependencies {
            $0.continuousClock = ImmediateClock()
        } operation: {
            let state = DecodeEffectState(config: DecodeEffect(duration: 0.1, charsets: [.latin]))
            state.startLoading(placeholderLength: 4)
            #expect(state.isAnimating)
            state.decode(to: "DONE")
            await state.task?.value
            #expect(state.displayText == "DONE")
            #expect(!state.isAnimating)
        }
    }

    @MainActor
    @Test("decode gradually locks characters from left when source returns 0")
    func decodeProgressiveLock() async {
        await withDependencies {
            $0.continuousClock = ImmediateClock()
            $0.randomSource = SequenceRandomSource(values: [0])
        } operation: {
            let state = DecodeEffectState(config: DecodeEffect(duration: 0.3, charsets: [.latin]))
            var snapshots: [String] = []
            state.onUpdate = { snapshots.append($0) }
            state.decode(to: "ABCD")
            await state.task?.value

            #expect(state.displayText == "ABCD")
            let hadPartial = snapshots.contains { frame in
                frame != "ABCD" && frame.contains("A")
            }
            #expect(hadPartial, "expected at least one frame with partial lock visible")
        }
    }

    @MainActor
    @Test("stop prevents decode completion callback")
    func stopPreventsCallback() async {
        let testClock = TestClock()
        await withDependencies {
            $0.continuousClock = testClock
        } operation: {
            let state = DecodeEffectState(config: DecodeEffect(duration: 1.0, charsets: [.latin]))
            var completed = false
            state.decode(to: "Test") { completed = true }

            await Task.yield()

            state.stop()
            await testClock.advance(by: .seconds(2))

            #expect(!completed)
            #expect(!state.isAnimating)
        }
    }
}
