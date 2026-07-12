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
        let gateway = FakeConfigWatchGateway()
        let useCase = StubConfigUseCase(outcome: .updated(.init(configDir: "/x")))
        let interactor = withDependencies {
            $0.configWatchGateway = gateway
            $0.configUseCase = useCase
            $0.continuousClock = ImmediateClock()
        } operation: {
            ConfigInteractorImpl()
        }

        final class Observed: @unchecked Sendable {
            var pinged = false
            var lastInvalid: ConfigReloadFailure?
        }
        let observed = Observed()
        let pingCancellable = interactor.appStyleChanges.sink { observed.pinged = true }
        let invalidCancellable = interactor.invalidConfig.sink { observed.lastInvalid = $0 }
        interactor.start()
        gateway.fire()  // 監視イベント発火

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
        let gateway = FakeConfigWatchGateway()
        let useCase = StubConfigUseCase(outcome: .invalid(.init(path: "/c.toml", reason: .decode("bad"))))
        let interactor = withDependencies {
            $0.configWatchGateway = gateway
            $0.configUseCase = useCase
            $0.continuousClock = ImmediateClock()
        } operation: {
            ConfigInteractorImpl()
        }

        final class Observed: @unchecked Sendable {
            var invalid: ConfigReloadFailure?
            var pinged = false
        }
        let observed = Observed()
        let invalidCancellable = interactor.invalidConfig.sink { observed.invalid = $0 }
        let pingCancellable = interactor.appStyleChanges.sink { observed.pinged = true }
        interactor.start()
        gateway.fire()

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
}

// MARK: - Fakes / Stubs

private final class FakeConfigWatchGateway: ConfigWatchGateway, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?

    func watch(directory: String, onChange: @escaping @Sendable () -> Void) -> (any ConfigWatchToken)? {
        lock.withLock { handler = onChange }
        return FakeConfigWatchToken()
    }

    func fire() {
        lock.withLock { handler }?()
    }
}

private struct FakeConfigWatchToken: ConfigWatchToken {
    func stop() {}
}

private struct StubConfigUseCase: ConfigUseCase, Sendable {
    let outcome: ConfigReloadOutcome

    var appStyle: AppStyle { .init() }
    func reload() -> ConfigReloadOutcome { outcome }
    func template(format: ConfigFormat) -> String? { nil }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { "" }
    var existingConfigPath: String? { "/tmp/config.toml" }  // watch dir 解決に非nilが要る
}
