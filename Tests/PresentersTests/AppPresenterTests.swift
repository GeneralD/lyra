import Combine
import ConcurrencyExtras
import CoreGraphics
import Dependencies
import Domain
import TestSupport
import Testing

@testable import Presenters

// MARK: - Stub

private struct StubScreenInteractor: ScreenInteractor, @unchecked Sendable {
    var screenSelector: ScreenSelector = .main
    var screenDebounce: Double = 5
    var layoutToReturn: ScreenLayout
    var screenChanges: AnyPublisher<Void, Never> = Empty().eraseToAnyPublisher()

    func resolveLayout() -> ScreenLayout { layoutToReturn }
}

private final class MutableInteractor: ScreenInteractor, @unchecked Sendable {
    var screenSelector: ScreenSelector
    var screenDebounce: Double
    var layoutToReturn: ScreenLayout
    let changes = PassthroughSubject<Void, Never>()
    /// Records the upstream cancellation `AppPresenter.stop()` triggers via
    /// `cancellables.removeAll()`, so tests can await the teardown itself
    /// instead of guessing how long propagation takes.
    let screenChangesCancellations = Collector<Void>()
    var screenChanges: AnyPublisher<Void, Never> {
        changes
            .handleEvents(receiveCancel: { [screenChangesCancellations] in
                screenChangesCancellations.append(())
            })
            .eraseToAnyPublisher()
    }

    init(layout: ScreenLayout, selector: ScreenSelector = .main, debounce: Double = 5) {
        layoutToReturn = layout
        screenSelector = selector
        screenDebounce = debounce
    }

    func resolveLayout() -> ScreenLayout { layoutToReturn }
}

// MARK: - Tests

@Suite("AppPresenter", .timeLimit(.minutes(1)))
struct AppPresenterTests {

    @MainActor
    @Test("start() sets layout from ScreenInteractor")
    func startSetsLayout() async {
        let expected = ScreenLayout(
            windowFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            hostingFrame: CGRect(x: 0, y: 0, width: 1920, height: 1040),
            screenOrigin: CGPoint(x: 0, y: 40)
        )

        let presenter = withDependencies {
            $0.screenInteractor = StubScreenInteractor(layoutToReturn: expected)
        } operation: {
            AppPresenter()
        }
        presenter.start()

        await settle(presenter.$layout) { $0.windowFrame == expected.windowFrame }

        #expect(presenter.layout.windowFrame == expected.windowFrame)
        #expect(presenter.layout.hostingFrame == expected.hostingFrame)
        #expect(presenter.layout.screenOrigin == expected.screenOrigin)
    }

    @MainActor
    @Test("screenChanges publisher triggers layout refresh")
    func screenChangesUpdates() async {
        let initial = ScreenLayout(
            windowFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            hostingFrame: CGRect(x: 0, y: 0, width: 1920, height: 1040),
            screenOrigin: CGPoint(x: 0, y: 40)
        )
        let updated = ScreenLayout(
            windowFrame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            hostingFrame: CGRect(x: 0, y: 0, width: 2560, height: 1400),
            screenOrigin: CGPoint(x: 0, y: 40)
        )

        let interactor = MutableInteractor(layout: initial)

        let presenter = withDependencies {
            $0.screenInteractor = interactor
        } operation: {
            AppPresenter()
        }
        presenter.start()

        // Wait for initial Just(()) to flush
        await settle(presenter.$layout) { $0.windowFrame == initial.windowFrame }
        #expect(presenter.layout.windowFrame == initial.windowFrame)

        interactor.layoutToReturn = updated
        interactor.changes.send(())

        await settle(presenter.$layout) { $0.windowFrame == updated.windowFrame }

        #expect(presenter.layout.windowFrame == updated.windowFrame)
        #expect(presenter.layout.hostingFrame == updated.hostingFrame)
    }

    @MainActor
    @Test("default layout is zero before start()")
    func defaultLayoutBeforeStart() {
        withDependencies {
            $0.screenInteractor = StubScreenInteractor(
                layoutToReturn: ScreenLayout(
                    windowFrame: CGRect(x: 0, y: 0, width: 100, height: 100)
                )
            )
        } operation: {
            let presenter = AppPresenter()

            // Before start(), layout should be the default (.zero)
            #expect(presenter.layout.windowFrame == .zero)
            #expect(presenter.layout.hostingFrame == .zero)
        }
    }

    @MainActor
    @Test("vacant mode triggers periodic recalculation")
    func vacantPolling() async {
        let initial = ScreenLayout(windowFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let updated = ScreenLayout(windowFrame: CGRect(x: 0, y: 0, width: 2560, height: 1440))

        let interactor = MutableInteractor(layout: initial, selector: .vacant, debounce: 1)
        let testClock = TestClock()
        let presenter = withDependencies {
            $0.screenInteractor = interactor
            $0.continuousClock = testClock
        } operation: {
            AppPresenter()
        }

        presenter.start()
        #expect(presenter.layout.windowFrame == initial.windowFrame)

        interactor.layoutToReturn = updated

        // Let the polling task reach `clock.sleep` before advancing.
        await Task.yield()
        await Task.yield()
        await testClock.advance(by: .seconds(1))

        await settle(presenter.$layout) { $0.windowFrame == updated.windowFrame }

        #expect(presenter.layout.windowFrame == updated.windowFrame)
        presenter.stop()
    }

    @MainActor
    @Test("stop() cancels vacant polling")
    func stopCancelsPolling() async {
        let layout = ScreenLayout(windowFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let presenter = withDependencies {
            $0.screenInteractor = StubScreenInteractor(
                screenSelector: .vacant,
                layoutToReturn: layout
            )
            $0.continuousClock = TestClock()
        } operation: {
            AppPresenter()
        }

        presenter.start()
        presenter.stop()
        // No crash or infinite loop — polling task is cancelled
    }

    @MainActor
    @Test("bind(ripplePresenter:) pushes current rippleRect on subscription")
    func bindRippleInitial() async {
        let layout = ScreenLayout(
            windowFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            hostingFrame: CGRect(x: 0, y: 0, width: 1920, height: 1040),
            screenOrigin: CGPoint(x: 100, y: 40)
        )

        let interactor = MutableInteractor(layout: layout)
        let (presenter, ripple) = withDependencies {
            $0.screenInteractor = interactor
        } operation: {
            (AppPresenter(), RipplePresenter())
        }

        presenter.bind(ripplePresenter: ripple)
        presenter.start()

        // ripple.screenOrigin isn't @Published; bind() subscribes to $layout
        // synchronously, so settling on it also proves the ripple was updated.
        await settle(presenter.$layout) { $0.screenOrigin == CGPoint(x: 100, y: 40) }
        #expect(ripple.screenOrigin == CGPoint(x: 100, y: 40))
    }

    @MainActor
    @Test("bind(ripplePresenter:) forwards subsequent layout changes")
    func bindRippleForwardsUpdates() async {
        let initial = ScreenLayout(
            windowFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            hostingFrame: CGRect(x: 0, y: 0, width: 1920, height: 1040),
            screenOrigin: CGPoint(x: 0, y: 40)
        )
        let updated = ScreenLayout(
            windowFrame: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
            hostingFrame: CGRect(x: 0, y: 0, width: 1920, height: 1040),
            screenOrigin: CGPoint(x: 1920, y: 40)
        )

        let interactor = MutableInteractor(layout: initial)
        let (presenter, ripple) = withDependencies {
            $0.screenInteractor = interactor
        } operation: {
            (AppPresenter(), RipplePresenter())
        }

        presenter.bind(ripplePresenter: ripple)
        presenter.start()
        // ripple.screenOrigin isn't @Published; settle on the $layout it derives from.
        await settle(presenter.$layout) { $0.screenOrigin == CGPoint(x: 0, y: 40) }
        #expect(ripple.screenOrigin == CGPoint(x: 0, y: 40))

        interactor.layoutToReturn = updated
        interactor.changes.send(())

        await settle(presenter.$layout) { $0.screenOrigin == CGPoint(x: 1920, y: 40) }
        #expect(ripple.screenOrigin == CGPoint(x: 1920, y: 40))
    }

    @MainActor
    @Test("onWindowFrameChange fires on every screen-change signal, even when the resolved frame is unchanged (regression: #265)")
    func onWindowFrameChangeReassertsUnchangedFrame() async {
        let first = ScreenLayout(windowFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let sameFrame = ScreenLayout(
            windowFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            hostingFrame: CGRect(x: 0, y: 0, width: 1920, height: 1040)
        )
        let different = ScreenLayout(windowFrame: CGRect(x: 0, y: 0, width: 2560, height: 1440))

        let interactor = MutableInteractor(layout: first)
        let presenter = withDependencies {
            $0.screenInteractor = interactor
        } operation: {
            AppPresenter()
        }

        final class Counter: @unchecked Sendable {
            @Published var count = 0
        }
        let counter = Counter()

        presenter.start()
        // Wait for initial layout to flush
        await settle(presenter.$layout) { $0.windowFrame == first.windowFrame }
        // Subscribe after start so the current layout is dropped.
        presenter.onWindowFrameChange { _ in counter.count += 1 }

        // Same windowFrame (different hostingFrame) → still fires so the window
        // can heal from system-side moves during display reconfiguration.
        interactor.layoutToReturn = sameFrame
        interactor.changes.send(())

        // Identical layout → still fires for the same reason.
        interactor.changes.send(())

        // Different windowFrame → fires.
        interactor.layoutToReturn = different
        interactor.changes.send(())

        await settle(counter.$count) { $0 >= 3 }
        #expect(counter.count == 3)
    }

    @MainActor
    @Test("stop() unsubscribes from screenChanges")
    func stopUnsubscribesScreenChanges() async {
        let initial = ScreenLayout(windowFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let updated = ScreenLayout(windowFrame: CGRect(x: 0, y: 0, width: 2560, height: 1440))

        let interactor = MutableInteractor(layout: initial)
        let presenter = withDependencies {
            $0.screenInteractor = interactor
        } operation: {
            AppPresenter()
        }

        presenter.start()
        await settle(presenter.$layout) { $0.windowFrame == initial.windowFrame }
        presenter.stop()

        // Wait for the actual unsubscription (cancellables.removeAll() cancelling
        // the screenChanges pipeline), not a guessed propagation delay. Once the
        // publisher has observed its subscriber cancel, a later send(_:) has no
        // subscriber left and is a synchronous no-op.
        await interactor.screenChangesCancellations.waitForCount(1)

        interactor.layoutToReturn = updated
        interactor.changes.send(())

        #expect(presenter.layout.windowFrame == initial.windowFrame)
    }

    @MainActor
    @Test("stop() releases bindings")
    func stopReleasesBindings() async {
        let layout = ScreenLayout(windowFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let (presenter, ripple) = withDependencies {
            $0.screenInteractor = StubScreenInteractor(layoutToReturn: layout)
        } operation: {
            (AppPresenter(), RipplePresenter())
        }

        presenter.bind(ripplePresenter: ripple)
        presenter.start()
        presenter.stop()
        // No assertion — exercises the cancellables.removeAll() branch.
    }

    @MainActor
    @Test("config ping re-resolves the layout (screen re-selection hot-reload)")
    func configPingReResolvesLayout() async {
        let initial = ScreenLayout(windowFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let updated = ScreenLayout(windowFrame: CGRect(x: 0, y: 0, width: 3840, height: 2160))

        let screen = MutableInteractor(layout: initial)
        let config = FakeConfigInteractor()

        let presenter = withDependencies {
            $0.screenInteractor = screen
            $0.configInteractor = config
        } operation: {
            AppPresenter()
        }

        presenter.start()
        await settle(presenter.$layout) { $0.windowFrame == initial.windowFrame }

        // A config reload changed the screen selector — the interactor now resolves
        // a different display. The ping must re-resolve without a restart.
        screen.layoutToReturn = updated
        config.fire()
        await flushMainQueue()
        await settle(presenter.$layout) { $0.windowFrame == updated.windowFrame }

        #expect(presenter.layout.windowFrame == updated.windowFrame)
        presenter.stop()
    }

    @MainActor
    @Test("config ping that switches selector to vacant starts polling")
    func configPingStartsVacantPolling() async {
        let initial = ScreenLayout(windowFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let polled = ScreenLayout(windowFrame: CGRect(x: 0, y: 0, width: 2560, height: 1440))

        // Starts in .main (no polling). A config reload switches to .vacant.
        let screen = MutableInteractor(layout: initial, selector: .main, debounce: 1)
        let config = FakeConfigInteractor()
        let testClock = TestClock()

        let presenter = withDependencies {
            $0.screenInteractor = screen
            $0.configInteractor = config
            $0.continuousClock = testClock
        } operation: {
            AppPresenter()
        }

        presenter.start()
        await settle(presenter.$layout) { $0.windowFrame == initial.windowFrame }

        // Switch to vacant via reload. layoutToReturn is still `initial`, so the
        // immediate re-resolve does not change the layout — only polling can.
        screen.screenSelector = .vacant
        config.fire()
        await flushMainQueue()
        #expect(presenter.layout.windowFrame == initial.windowFrame)

        // Polling is now armed: a later layout change is picked up on the next tick.
        screen.layoutToReturn = polled
        await Task.yield()
        await Task.yield()
        await testClock.advance(by: .seconds(1))
        await settle(presenter.$layout) { $0.windowFrame == polled.windowFrame }

        #expect(presenter.layout.windowFrame == polled.windowFrame)
        presenter.stop()
    }
}
