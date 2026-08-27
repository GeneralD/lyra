/// Steps the main queue forward until `condition` holds.
///
/// For waits on work that lands on the main queue in order — a `@MainActor`
/// `Task`, an `AsyncStream` the presenter consumes there, a
/// `.receive(on: DispatchQueue.main)` hop. Each `Task.yield()` re-enqueues the
/// test behind everything already queued on main, so one step lets exactly the
/// rounds queued ahead run, in order. The wait is on *order*, never on the wall
/// clock: a slow CI runner stretches each round, it cannot reorder a round past
/// the assertion the way a deadline poll can — the poll's expired continuation
/// runs *before* the block queued behind it (#347).
///
/// Not a general await for thread-pool work: a nonisolated `Task` the code
/// under test spawns is observed only once its effect reaches the main queue,
/// so a condition fed purely from the pool is a bet on rounds again. Redirecting
/// the pool onto the main actor for the test
/// (`ConcurrencyExtras.uncheckedUseMainSerialExecutor`) was tried and rejected:
/// the hook is process-wide, and under Swift Testing's parallel run it stalled
/// twelve tests across six unrelated targets.
///
/// `budget` bounds a genuine regression — an event the code never emits — in
/// rounds, not seconds. A condition still false after thousands of rounds is a
/// failing test, not a slow one.
@MainActor
func drain(budget: Int = 10_000, until condition: @MainActor () -> Bool) async {
    guard budget > 0, !condition() else { return }
    await Task.yield()
    await drain(budget: budget - 1, until: condition)
}
