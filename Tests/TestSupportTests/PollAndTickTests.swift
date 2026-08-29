import Foundation
import TestSupport
import Testing

/// Pins the two bounded waits (#349): `pollUntil` returns on the first interval that
/// sees the condition and reports an expiry instead of hanging; `tickUntil` counts
/// ticks, not seconds, and reports a budget that ran out. Both end on cancellation, so
/// a suite's `.timeLimit` cancelling the test task is reported rather than spun out.
@Suite(.timeLimit(.minutes(1)))
struct PollUntilTests {
    @Test func conditionAlreadyTrueReturnsWithoutSleeping() async {
        // An interval longer than the suite's time limit: if the poll slept even
        // once before checking, the limit would report it — no wall clock needed.
        #expect(await pollUntil(interval: .seconds(120)) { true })
    }

    @Test func returnsOnceTheConditionHolds() async {
        let flag = Collector<Void>()
        Task.detached {
            try? await Task.sleep(for: .milliseconds(20))
            flag.append(())
        }
        #expect(await pollUntil(timeout: .seconds(5)) { flag.count == 1 })
    }

    @Test func reportsExpiryInsteadOfHanging() async {
        #expect(await pollUntil(timeout: .milliseconds(30)) { false } == false)
    }

    @Test func cancellationEndsThePoll() async {
        // Without the cancellation check the poll would spin to its own deadline —
        // longer than the suite's limit here — once `.timeLimit` cancels the test.
        let poll = Task { await pollUntil(timeout: .seconds(120)) { false } }
        poll.cancel()
        #expect(await poll.value == false)
    }

    @Test func cancellationWinsOverAConditionThatAlreadyHolds() async {
        let poll = Task { await pollUntil { true } }
        poll.cancel()
        #expect(await poll.value == false)
    }
}

@Suite(.timeLimit(.minutes(1)))
struct TickUntilTests {
    @MainActor
    final class Stepper {
        private(set) var ticks = 0
        func tick() { ticks += 1 }
    }

    @Test @MainActor func stopsAtTheFirstSatisfyingTick() async {
        let stepper = Stepper()
        #expect(await tickUntil(tick: stepper.tick) { stepper.ticks == 3 })
        #expect(stepper.ticks == 3)
    }

    @Test @MainActor func spendsTheWholeBudgetWhenTheConditionNeverHolds() async {
        let stepper = Stepper()
        #expect(await tickUntil(5, tick: stepper.tick) { false } == false)
        #expect(stepper.ticks == 5)
    }

    @Test @MainActor func cancellationReturnsWithoutSpendingTheBudget() async {
        let stepper = Stepper()
        // The task is cancelled before it runs — the test holds the main actor until
        // it awaits — so the loop sees the cancellation before its first tick and
        // returns; without the check, a cancelled sleep returns at once and the loop
        // spins the whole budget.
        let drive = Task { @MainActor in
            await tickUntil(100_000, tick: stepper.tick) { false }
        }
        drive.cancel()
        #expect(await drive.value == false)
        #expect(stepper.ticks == 0)
    }
}
