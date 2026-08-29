import Foundation
import TestSupport
import Testing

/// Pins `suspendUntilCancelled()` (#353): it returns because of the cancel and for no
/// other reason, and a cancel that is already in effect does not park at all.
@Suite(.timeLimit(.minutes(1)))
struct SuspendUntilCancelledTests {
    @Test func returnsOnceTheTaskIsCancelled() async {
        let parked = Collector<Void>()
        let resumed = Collector<Void>()
        let task = Task {
            parked.append(())
            await suspendUntilCancelled()
            resumed.append(())
        }
        // The task is inside the call (or about to enter it) before the cancel lands;
        // either way the cancel is the only thing that can resume it.
        await parked.waitForCount(1)
        #expect(resumed.count == 0)
        task.cancel()
        await task.value
        #expect(resumed.count == 1)
    }

    @Test func returnsAtOnceWhenAlreadyCancelled() async {
        let task = Task {
            await suspendUntilCancelled()
            return Task.isCancelled
        }
        task.cancel()
        // With the cancel already in effect there is nothing to wait for; a park that
        // ignored it would hang here until the suite's time limit reported it.
        #expect(await task.value)
    }
}
