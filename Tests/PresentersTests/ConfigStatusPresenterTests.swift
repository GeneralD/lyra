import Combine
import Dependencies
import Domain
import Foundation
import Testing
import os

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
        let publisher =
            subject
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

    @Test("start()/stop() が ConfigInteractor の watch lifecycle を駆動する")
    func ownsInteractorLifecycle() {
        // The presenter fronts the interactor so the AppRouter wireframe never
        // reaches into the Interactor layer directly: start() arms the watch,
        // stop() disarms it.
        let interactor = StubConfigInteractor()
        let presenter = withDependencies {
            $0.configInteractor = interactor
        } operation: {
            ConfigStatusPresenter()
        }

        #expect(interactor.startCount == 0)
        presenter.start()
        #expect(interactor.startCount == 1)
        #expect(interactor.stopCount == 0)

        presenter.stop()
        #expect(interactor.stopCount == 1)
    }

    @Test("二重 start() は購読も interactor.start() も重複しない（冪等性）")
    func duplicateStartIsIdempotent() {
        let interactor = StubConfigInteractor()
        let presenter = withDependencies {
            $0.configInteractor = interactor
        } operation: {
            ConfigStatusPresenter()
        }

        presenter.start()
        presenter.start()
        #expect(interactor.startCount == 1)

        // A stop()/start() cycle still restarts cleanly after the guard.
        presenter.stop()
        presenter.start()
        #expect(interactor.startCount == 2)
        presenter.stop()
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
    private let counts = OSAllocatedUnfairLock(initialState: (start: 0, stop: 0))
    init(invalid: AnyPublisher<ConfigReloadFailure?, Never> = Empty().eraseToAnyPublisher()) {
        self.invalid = invalid
    }
    var appStyleChanges: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }
    var invalidConfig: AnyPublisher<ConfigReloadFailure?, Never> { invalid }
    var startCount: Int { counts.withLock { $0.start } }
    var stopCount: Int { counts.withLock { $0.stop } }
    func start() { counts.withLock { $0.start += 1 } }
    func stop() { counts.withLock { $0.stop += 1 } }
}
