import Foundation

/// Records the values a test subject emits from *any* context — a Combine sink on
/// the interactor's worker queue, a thread-pool `Task`, a gateway callback — and lets
/// a test suspend until the recording satisfies a condition.
///
/// The wait is resumed by the write itself: `append(_:)` checks every pending waiter
/// under the lock and resumes the ones whose condition now holds. Nothing is assumed
/// about time or executor ordering, and a condition that already holds returns at
/// once. This is the spy-side counterpart of `settle(_:until:)`, for state that has
/// no publisher to await (#349). A value that never arrives is a hang rather than a
/// flake, so give the suite `.timeLimit`.
///
/// Generalised from `TrackInteractorRaceTests.UpdateCollector`, which resumed a
/// `CheckedContinuation` on element arrival; the deadline-polling collectors it
/// replaces (`waitForCount(_:timeout:)` over an `NSLock`ed array) expired *before*
/// the emission they were waiting for whenever CI stalled the worker.
public final class Collector<Element: Sendable>: @unchecked Sendable {
    private struct Waiter {
        let id: UUID
        let condition: @Sendable ([Element]) -> Bool
        let continuation: CheckedContinuation<Void, Never>
    }

    private let lock = NSLock()
    private var storage: [Element] = []
    private var waiters: [Waiter] = []

    public init() {}

    /// Everything recorded so far, in arrival order.
    public var values: [Element] { lock.withLock { storage } }

    public var count: Int { lock.withLock { storage.count } }

    public var last: Element? { lock.withLock { storage.last } }

    public func contains(where predicate: (Element) -> Bool) -> Bool {
        lock.withLock { storage.contains(where: predicate) }
    }

    /// Records `element` and resumes every waiter whose condition the recording
    /// now satisfies.
    public func append(_ element: Element) {
        let ready = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            storage.append(element)
            let matched = waiters.filter { $0.condition(storage) }
            waiters.removeAll { waiter in matched.contains { $0.id == waiter.id } }
            return matched.map(\.continuation)
        }
        for continuation in ready {
            continuation.resume()
        }
    }

    /// Suspends until the recorded values satisfy `condition` — at once if they
    /// already do. No deadline: the suite's `.timeLimit` reports a value that never
    /// arrives.
    public func settle(until condition: @escaping @Sendable ([Element]) -> Bool) async {
        let id = UUID()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let alreadySatisfied = lock.withLock { () -> Bool in
                if condition(storage) { return true }
                waiters.append(Waiter(id: id, condition: condition, continuation: continuation))
                return false
            }
            if alreadySatisfied {
                continuation.resume()
            }
        }
    }

    /// Suspends until at least `target` values have been recorded.
    public func waitForCount(_ target: Int) async {
        await settle { $0.count >= target }
    }

    /// Suspends until a recorded value satisfies `predicate` and returns the first
    /// such value.
    @discardableResult
    public func waitFor(predicate: @escaping @Sendable (Element) -> Bool) async -> Element {
        await settle { $0.contains(where: predicate) }
        return lock.withLock { storage.first(where: predicate)! }
    }
}
