import Combine
import Dependencies
import Domain
import Foundation
import Testing

@testable import Presenters

@MainActor
@Suite("ConfigStatusPresenter")
struct ConfigStatusPresenterTests {
    @Test("invalidConfig 発火で @Published が更新される")
    func reflectsInvalid() async {
        let subject = CurrentValueSubject<ConfigReloadFailure?, Never>(nil)
        let presenter = withDependencies {
            $0.configInteractor = StubConfigInteractor(invalid: subject.eraseToAnyPublisher())
        } operation: {
            ConfigStatusPresenter()
        }
        presenter.start()
        defer { presenter.stop() }

        subject.send(.init(path: "/c.toml", reason: .unreadable))
        await waitUntil { presenter.invalidConfig != nil }
        #expect(presenter.invalidConfig?.reason == .unreadable)

        subject.send(nil)
        await waitUntil { presenter.invalidConfig == nil }
        #expect(presenter.invalidConfig == nil)
    }

    @Test("stop() でストリーム購読が解除される")
    func stopUnsubscribes() async {
        let subject = CurrentValueSubject<ConfigReloadFailure?, Never>(nil)
        let cancelBox = CancelBox()
        let publisher = subject
            .handleEvents(receiveCancel: { cancelBox.markCancelled() })
            .eraseToAnyPublisher()
        let presenter = withDependencies {
            $0.configInteractor = StubConfigInteractor(invalid: publisher)
        } operation: {
            ConfigStatusPresenter()
        }
        presenter.start()
        presenter.stop()

        // Deterministically wait for the subscription to actually be torn
        // down (poll-until-deadline) instead of a fixed sleep.
        await waitUntil { cancelBox.cancelled }
        #expect(cancelBox.cancelled)

        subject.send(.init(path: "/c.toml", reason: .unreadable))
        await Task.yield()
        #expect(presenter.invalidConfig == nil)
    }
}

private final class CancelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelled = false
    var cancelled: Bool { lock.withLock { _cancelled } }
    func markCancelled() { lock.withLock { _cancelled = true } }
}

private final class StubConfigInteractor: ConfigInteractor, @unchecked Sendable {
    let invalid: AnyPublisher<ConfigReloadFailure?, Never>
    init(invalid: AnyPublisher<ConfigReloadFailure?, Never>) { self.invalid = invalid }
    var appStyleChanges: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }
    var invalidConfig: AnyPublisher<ConfigReloadFailure?, Never> { invalid }
    func start() {}
    func stop() {}
}
