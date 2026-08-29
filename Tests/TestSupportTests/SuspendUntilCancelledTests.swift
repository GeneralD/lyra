import Foundation
import TestSupport
import Testing

/// Pins `suspendUntilCancelled()` (#353): it returns `true` because of the cancel and for
/// no other reason, a cancel already in effect does not park at all, and a subject that
/// never cancels is reported by the guardrail instead of hanging the run.
@Suite(.timeLimit(.minutes(1)))
struct SuspendUntilCancelledTests {
    @Test func returnsOnceTheTaskIsCancelled() async {
        let parked = Collector<Void>()
        let resumed = Collector<Bool>()
        let task = Task {
            parked.append(())
            resumed.append(await suspendUntilCancelled())
        }
        // The task is inside the call (or about to enter it) before the cancel lands;
        // either way the cancel is the only thing that can resume it within the limit.
        await parked.waitForCount(1)
        #expect(resumed.count == 0)
        task.cancel()
        await task.value
        #expect(resumed.values == [true])
    }

    @Test func returnsAtOnceWhenAlreadyCancelled() async {
        let task = Task {
            // The only way past the first call within the limit is the cancel, so the
            // second call is entered with the cancel provably in effect — whatever the
            // scheduling — and must not park.
            await suspendUntilCancelled()
            return await suspendUntilCancelled()
        }
        task.cancel()
        #expect(await task.value)
    }

    @Test func reportsTheGuardrailInsteadOfHanging() async {
        // A short guardrail on the failing path: no cancel ever comes, and the call
        // still returns, saying so.
        #expect(await suspendUntilCancelled(guardrail: .milliseconds(20)) == false)
    }
}
