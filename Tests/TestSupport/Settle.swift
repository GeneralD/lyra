import Combine

/// Suspends until `publisher` emits a value that satisfies `condition`.
///
/// The wait is on the event itself — the `@Published` write a spy or presenter
/// performs when the work lands — not on time and not on the scheduler. The
/// deadline poll this replaced (#347) raced its own expiry against the
/// `.receive(on: DispatchQueue.main)` hop that delivers the value, so a stalled
/// CI runner asserted before the value landed; awaiting the publisher removes
/// that race by construction. Nothing is assumed about executor ordering: the
/// continuation resumes when the value arrives, and a value published before
/// the call satisfies it immediately (`@Published` replays its current value
/// to a new subscriber).
///
/// A value that never arrives is a hang, not a flake — every suite that waits
/// this way carries `.timeLimit` so a regression is reported, not waited on.
@MainActor
public func settle<Value>(_ publisher: Published<Value>.Publisher, until condition: (Value) -> Bool) async {
    for await value in publisher.values where condition(value) { return }
}
