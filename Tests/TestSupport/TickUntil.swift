/// Drives a subject that only advances when the test ticks it — a presenter whose
/// display link the test stands in for — until `condition` holds, and reports whether
/// it did within `maxTicks`.
///
/// The bound is a tick *budget*, not a wall clock (#349): the subject's next state is
/// a function of how many times it was ticked, so a loaded CI simply spends more of
/// the budget while an idle run returns on the first tick that satisfies the
/// condition. `settle(_:until:)` cannot serve these sites because the writer of the
/// awaited value is the test itself — awaiting the publisher without ticking would
/// hang. The 1 ms sleep between ticks yields to the main queue so a value hopping
/// through `receive(on: .main)` lands before the next tick reads it.
///
/// A `false` result is also the shape of a negative check: ticking a paused subject
/// `n` times and asserting the condition never held proves "nothing happens" in tick
/// count rather than in seconds. Cancellation — a suite's `.timeLimit` expiring —
/// returns `false` at the next tick instead of spending the rest of the budget.
@MainActor
@discardableResult
public func tickUntil(
    _ maxTicks: Int = 4000,
    tick: () -> Void,
    until condition: () -> Bool
) async -> Bool {
    for _ in 0..<maxTicks {
        tick()
        if condition() { return true }
        guard !Task.isCancelled else { return false }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return false
}
