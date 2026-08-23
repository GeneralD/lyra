import Combine
import Domain
import Foundation

/// Test double for `ConfigInteractor` that lets a test fire an `appStyleChanges`
/// ping on demand, simulating a config hot-reload without the real file watcher.
/// Shared across the presenter tests that exercise the `applyStyle()` seam (#41).
final class FakeConfigInteractor: ConfigInteractor, @unchecked Sendable {
    private let appStyleSubject = PassthroughSubject<Void, Never>()
    private let invalidSubject = CurrentValueSubject<ConfigReloadFailure?, Never>(nil)

    var appStyleChanges: AnyPublisher<Void, Never> { appStyleSubject.eraseToAnyPublisher() }
    var invalidConfig: AnyPublisher<ConfigReloadFailure?, Never> { invalidSubject.eraseToAnyPublisher() }
    func start() {}
    func stop() {}

    /// Emits an `appStyleChanges` ping, exactly as a successful reload would.
    func fire() { appStyleSubject.send(()) }
}

/// Deterministically drains the main dispatch queue. A presenter's
/// `appStyleChanges` sink hops through `.receive(on: DispatchQueue.main)`, which
/// schedules its delivery with `DispatchQueue.main.async`; a marker enqueued
/// afterward runs strictly after it (FIFO). Awaiting the marker therefore
/// guarantees a fired ping's `applyStyle()` has run — with no fixed `Task.sleep`,
/// so it never flakes under CI load.
@MainActor
func flushMainQueue() async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        DispatchQueue.main.async { continuation.resume() }
    }
}
