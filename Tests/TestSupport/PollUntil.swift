/// Polls `condition` until it holds and reports whether it did before `timeout`.
///
/// Reserved for state that is merely *readable* — nothing in-process is written when
/// it changes, so there is no publisher or spy to await (#349): a file a subprocess
/// writes, a pid's liveness (`kill(pid, 0)`), a child the OS has yet to reap. Anything
/// a callback or a `@Published` write announces belongs to `Collector` /
/// `settle(_:until:)` instead, and anything the test itself drives belongs to
/// `tickUntil`; a deadline on those races the delivery it waits for.
///
/// The timeout is a guardrail on the failing path, never a delay on the passing one:
/// the poll returns on the first interval that sees the condition. Assert on the
/// result (`try #require(await pollUntil { … })`) so an expiry is reported where it
/// happened rather than as a downstream expectation. Cancellation ends the poll the
/// same way — `false` at once, checked before the condition, so a task that is
/// already cancelled never reports `true` — and a suite's `.timeLimit` cancelling
/// the test task does not leave the poll spinning to its own deadline.
@discardableResult
public func pollUntil(
    timeout: Duration = .seconds(3),
    interval: Duration = .milliseconds(10),
    _ condition: () -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while true {
        guard !Task.isCancelled else { return false }
        if condition() { return true }
        guard ContinuousClock.now < deadline else { return false }
        try? await Task.sleep(for: interval)
    }
}
