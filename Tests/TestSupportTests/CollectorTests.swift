import Combine
import TestSupport
import Testing

/// Pins the contract the migrated suites rely on (#349): a wait resumes on the
/// write, returns at once when already satisfied, records concurrent appends in
/// full, and — so `.timeLimit` can end a test whose value never arrives — gives up
/// when its task is cancelled instead of hanging.
@Suite(.timeLimit(.minutes(1)))
struct CollectorTests {
    @Test func conditionAlreadySatisfiedReturnsAtOnce() async {
        let collector = Collector<Int>()
        collector.append(1)
        await collector.waitForCount(1)
        #expect(collector.values == [1])
    }

    @Test func appendResumesPendingWait() async {
        let collector = Collector<Int>()
        let waiter = Task { await collector.waitFor { $0 == 2 } }
        collector.append(1)
        collector.append(2)
        #expect(await waiter.value == 2)
        #expect(collector.values == [1, 2])
    }

    @Test func concurrentAppendsAreAllRecorded() async {
        let collector = Collector<Int>()
        let waiter = Task { await collector.waitForCount(100) }
        await withTaskGroup(of: Void.self) { group in
            for value in 0..<100 {
                group.addTask { collector.append(value) }
            }
        }
        await waiter.value
        #expect(collector.values.sorted() == Array(0..<100))
    }

    @Test func cancellationEndsAWaitWhoseValueNeverArrives() async {
        let collector = Collector<Int>()
        let waiter = Task { await collector.waitFor { _ in true } }
        waiter.cancel()
        #expect(await waiter.value == nil)
        #expect(collector.count == 0)
    }
}

@Suite(.timeLimit(.minutes(1)))
struct SettleTests {
    @MainActor
    final class Box: ObservableObject {
        @Published var value = 0
    }

    @Test @MainActor func valueAlreadyPublishedReturnsAtOnce() async {
        let box = Box()
        box.value = 1
        await settle(box.$value) { $0 == 1 }
        #expect(box.value == 1)
    }

    @Test @MainActor func cancellationEndsAWaitWhoseValueNeverArrives() async {
        let box = Box()
        let waiter = Task { @MainActor in await settle(box.$value) { $0 == 1 } }
        waiter.cancel()
        await waiter.value
        #expect(box.value == 0)
    }
}
