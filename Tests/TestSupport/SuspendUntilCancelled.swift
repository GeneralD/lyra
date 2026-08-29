import Foundation

/// Suspends until the current task is cancelled — the stand-in for a request that
/// never answers, in a test double whose only way out is the subject cancelling it.
///
/// A `Task.sleep` of "long enough" models the same thing with a number that is not
/// part of the test's meaning, and turns a subject that fails to cancel into a wait of
/// that length before the assertion fails. Parking on cancellation says what the double
/// means: nothing but the cancel resumes it. The guardrail for a subject that never
/// cancels is the suite's `.timeLimit`, which cancels the test task and so releases
/// every double parked under it — the regression is reported, not spun out (#353).
///
/// Returns at once when the task is already cancelled.
public func suspendUntilCancelled() async {
    let latch = CancellationLatch()
    await withTaskCancellationHandler {
        await withCheckedContinuation { continuation in
            latch.park(continuation)
        }
    } onCancel: {
        latch.release()
    }
}

/// Hands the parked continuation to whichever of `park` and `release` comes second,
/// so a cancellation that lands before the continuation exists still resumes it.
/// Internal so `TestSupportTests` can pin both orders directly.
final class CancellationLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    func park(_ parked: CheckedContinuation<Void, Never>) {
        let resumeNow = lock.withLock {
            guard !released else { return true }
            continuation = parked
            return false
        }
        if resumeNow { parked.resume() }
    }

    func release() {
        let parked = lock.withLock {
            released = true
            defer { continuation = nil }
            return continuation
        }
        parked?.resume()
    }
}
