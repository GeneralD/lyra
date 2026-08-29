/// Suspends until the current task is cancelled — the stand-in for a request that
/// never answers, in a test double whose only way out is the subject cancelling it.
/// Returns `true` when the cancel arrived and `false` when the guardrail elapsed first.
///
/// The passing path never sees the guardrail: the subject cancels, the sleep throws, the
/// double resumes at once. The guardrail exists for the *failing* path, and it is
/// deliberately independent of task cancellation reaching this task. A suite's
/// `.timeLimit` cancels the test task, and that cancel propagates only through
/// structured children (`TaskGroup.addTask`, `async let`); a subject that regressed
/// into parking its probes on unstructured `Task { }`s would leave a cancel-only park
/// waiting forever, and a wait the run cannot end is a hang, not a failure (#349). With
/// the guardrail every parked double returns on its own, the double records that the
/// cancel never came, and the assertion fails where it should. The default matches the
/// one-minute suite limits, so a stuck subject surfaces at the same time either way.
///
/// Returns at once, `true`, when the task is already cancelled (#353).
@discardableResult
public func suspendUntilCancelled(guardrail: Duration = .seconds(60)) async -> Bool {
    do {
        try await Task.sleep(for: guardrail)
        return false
    } catch {
        return true
    }
}
