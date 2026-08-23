import Combine
import Dependencies
import Domain
import Foundation
import Testing

@testable import ConfigInteractor

@Suite("ConfigInteractorImpl")
struct ConfigInteractorImplTests {
    @Test(".updated で appStyleChanges が発火し invalidConfig が nil になる")
    func firesPingOnUpdate() async {
        let useCase = StubConfigUseCase(outcome: .updated(.init(configDir: "/x")))
        let interactor = withDependencies {
            $0.configUseCase = useCase
            $0.continuousClock = ImmediateClock()
        } operation: {
            ConfigInteractorImpl()
        }

        // Written from Combine sink callbacks and read from the polling loop —
        // lock every access so the cross-thread reads are well-defined.
        final class Observed: @unchecked Sendable {
            private let lock = NSLock()
            private var _pinged = false
            private var _lastInvalid: ConfigReloadFailure?
            var pinged: Bool {
                get { lock.withLock { _pinged } }
                set { lock.withLock { _pinged = newValue } }
            }
            var lastInvalid: ConfigReloadFailure? {
                get { lock.withLock { _lastInvalid } }
                set { lock.withLock { _lastInvalid = newValue } }
            }
        }
        let observed = Observed()
        let pingCancellable = interactor.appStyleChanges.sink { observed.pinged = true }
        let invalidCancellable = interactor.invalidConfig.sink { observed.lastInvalid = $0 }
        interactor.start()
        useCase.fire()  // Emit a watch event.

        let deadline = ContinuousClock.now + .seconds(2)
        while !observed.pinged, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(observed.pinged)
        #expect(observed.lastInvalid == nil)
        pingCancellable.cancel()
        invalidCancellable.cancel()
        interactor.stop()
    }

    @Test(".invalid で invalidConfig に failure が流れ ping は出ない")
    func surfacesFailureOnInvalid() async {
        let useCase = StubConfigUseCase(outcome: .invalid(.init(path: "/c.toml", reason: .decode("bad"))))
        let interactor = withDependencies {
            $0.configUseCase = useCase
            $0.continuousClock = ImmediateClock()
        } operation: {
            ConfigInteractorImpl()
        }

        // Written from Combine sink callbacks and read from the polling loop —
        // lock every access so the cross-thread reads are well-defined.
        final class Observed: @unchecked Sendable {
            private let lock = NSLock()
            private var _invalid: ConfigReloadFailure?
            private var _pinged = false
            var invalid: ConfigReloadFailure? {
                get { lock.withLock { _invalid } }
                set { lock.withLock { _invalid = newValue } }
            }
            var pinged: Bool {
                get { lock.withLock { _pinged } }
                set { lock.withLock { _pinged = newValue } }
            }
        }
        let observed = Observed()
        let invalidCancellable = interactor.invalidConfig.sink { observed.invalid = $0 }
        let pingCancellable = interactor.appStyleChanges.sink { observed.pinged = true }
        interactor.start()
        useCase.fire()

        let deadline = ContinuousClock.now + .seconds(2)
        while observed.invalid == nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(observed.invalid?.reason == .decode("bad"))
        #expect(!observed.pinged)
        invalidCancellable.cancel()
        pingCancellable.cancel()
        interactor.stop()
    }

    @Test("start() を複数回呼んでも watch は一度しか張られない（冪等性）")
    func startIsIdempotent() {
        let useCase = StubConfigUseCase(outcome: .updated(.init(configDir: "/x")))
        let interactor = withDependencies {
            $0.configUseCase = useCase
            $0.continuousClock = ImmediateClock()
        } operation: {
            ConfigInteractorImpl()
        }

        interactor.start()
        interactor.start()
        interactor.start()

        #expect(useCase.armCount == 1)
        interactor.stop()
    }

    @Test("stop() で watch token が止まり、再 start() で張り直せる")
    func stopReleasesWatchAndRestartRearms() {
        let useCase = StubConfigUseCase(outcome: .updated(.init(configDir: "/x")))
        let interactor = withDependencies {
            $0.configUseCase = useCase
            $0.continuousClock = ImmediateClock()
        } operation: {
            ConfigInteractorImpl()
        }

        interactor.start()
        interactor.stop()
        #expect(useCase.stopCount == 1)

        interactor.start()
        #expect(useCase.armCount == 2)
        interactor.stop()
    }

    @Test("watch を張れなかったとき（config dir 不在）は次の start() が再試行できる")
    func retriesArmingWhenWatchUnavailable() {
        let useCase = StubConfigUseCase(
            outcome: .updated(.init(configDir: "/x")), watchAvailable: false)
        let interactor = withDependencies {
            $0.configUseCase = useCase
            $0.continuousClock = ImmediateClock()
        } operation: {
            ConfigInteractorImpl()
        }

        interactor.start()
        // No token was armed, so the idempotency guard must not latch: a later
        // start() (after the directory appears) can try again.
        interactor.start()
        #expect(useCase.armCount == 0)
        interactor.stop()
    }

    @Test("stop() 後に pending の debounce が発火しても publish されない（teardown race）")
    func stopSuppressesPendingReload() async {
        let useCase = StubConfigUseCase(outcome: .updated(.init(configDir: "/x")))
        let testClock = TestClock()
        let interactor = withDependencies {
            $0.configUseCase = useCase
            $0.continuousClock = testClock
        } operation: {
            ConfigInteractorImpl()
        }

        // Written from a Combine sink callback and read after yields — lock
        // every access so the cross-thread reads are well-defined.
        final class Observed: @unchecked Sendable {
            private let lock = NSLock()
            private var _pinged = false
            var pinged: Bool {
                get { lock.withLock { _pinged } }
                set { lock.withLock { _pinged = newValue } }
            }
        }
        let observed = Observed()
        let cancellable = interactor.appStyleChanges.sink { observed.pinged = true }

        interactor.start()
        useCase.fire()  // The debounce task is now pending on clock.sleep.
        interactor.stop()  // Cancels: the sleep throws and the task still reaches applyReload.

        // The woken task must bail on the armed/cancelled guard instead of
        // publishing a spurious update after teardown.
        for _ in 0..<20 { await Task.yield() }
        #expect(!observed.pinged)
        cancellable.cancel()
    }
}

// MARK: - Stubs

/// Captures the interactor's `watchChanges` subscription so tests can fire
/// watch events and count arm/stop cycles without any gateway involvement —
/// the interactor only talks to its adjacent layer.
private final class StubConfigUseCase: ConfigUseCase, @unchecked Sendable {
    private let lock = NSLock()
    private let watchAvailable: Bool
    private var _outcome: ConfigReloadOutcome
    private var _handler: (@Sendable () -> Void)?
    private var _armCount = 0
    private var _stopCount = 0

    init(outcome: ConfigReloadOutcome, watchAvailable: Bool = true) {
        _outcome = outcome
        self.watchAvailable = watchAvailable
    }

    var armCount: Int { lock.withLock { _armCount } }
    var stopCount: Int { lock.withLock { _stopCount } }

    func fire() {
        lock.withLock { _handler }?()
    }

    var appStyle: AppStyle { .init() }
    func reload() -> ConfigReloadOutcome { lock.withLock { _outcome } }
    func template(format: ConfigFormat) -> String? { nil }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { "" }
    var existingConfigPath: String? { nil }

    func watchChanges(onChange: @escaping @Sendable () -> Void) -> (any ConfigWatchToken)? {
        lock.withLock {
            guard watchAvailable else { return nil }
            _armCount += 1
            _handler = onChange
            return StubWatchToken { [weak self] in self?.recordStop() }
        }
    }

    private func recordStop() {
        lock.withLock { _stopCount += 1 }
    }
}

private struct StubWatchToken: ConfigWatchToken {
    let onStop: @Sendable () -> Void
    func stop() { onStop() }
}
