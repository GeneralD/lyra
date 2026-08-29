import Combine
import Foundation

/// Records the values a test subject emits from *any* context — a Combine sink on
/// the interactor's worker queue, a thread-pool `Task`, a gateway callback — and lets
/// a test suspend until the recording satisfies a condition.
///
/// The recording lives in a `CurrentValueSubject` holding the append-only array, so
/// the wait is the same primitive as `settle(_:until:)`: a `for await` over the
/// subject's `values`, resumed by the write itself. Nothing is assumed about time or
/// executor ordering; a condition that already holds returns at once (the subject
/// replays its current value to a new subscriber); and because `AsyncPublisher`
/// honours task cancellation, a wait whose value never arrives ends when the suite's
/// `.timeLimit` cancels the test instead of hanging the run — give the suite
/// `.timeLimit`, and the regression is reported.
///
/// This is the spy-side counterpart of `settle(_:until:)`, for state that has no
/// publisher of its own (#349). The deadline-polling collectors it replaces
/// (`waitForCount(_:timeout:)` over an `NSLock`ed array) expired *before* the
/// emission they were waiting for whenever CI stalled the worker.
public final class Collector<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private let subject = CurrentValueSubject<[Element], Never>([])

    public init() {}

    /// Everything recorded so far, in arrival order.
    public var values: [Element] { lock.withLock { subject.value } }

    public var count: Int { values.count }

    public var last: Element? { values.last }

    public func contains(where predicate: (Element) -> Bool) -> Bool {
        values.contains(where: predicate)
    }

    /// Records `element`; the publish resumes every wait whose condition now holds.
    /// Appends are serialised so the subject's value only ever grows.
    public func append(_ element: Element) {
        lock.withLock { subject.value.append(element) }
    }

    /// Suspends until the recorded values satisfy `condition` — at once if they
    /// already do, and on task cancellation without them. No deadline: the suite's
    /// `.timeLimit` reports a value that never arrives.
    public func settle(until condition: @escaping @Sendable ([Element]) -> Bool) async {
        for await values in subject.values where condition(values) { return }
    }

    /// Suspends until at least `target` values have been recorded.
    public func waitForCount(_ target: Int) async {
        await settle { $0.count >= target }
    }

    /// Suspends until a recorded value satisfies `predicate` and returns the first
    /// such value — `nil` only when the wait was cancelled before one arrived.
    @discardableResult
    public func waitFor(predicate: @escaping @Sendable (Element) -> Bool) async -> Element? {
        await settle { $0.contains(where: predicate) }
        return values.first(where: predicate)
    }
}
