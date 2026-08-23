import Combine
import ConcurrencyExtras
import CoreGraphics
import Dependencies
import Domain
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
    var screenChanges: AnyPublisher<Void, Never> { changes.eraseToAnyPublisher() }

    init(layout: ScreenLayout, selector: ScreenSelector = .main, debounce: Double = 5) {
        layoutToReturn = layout
        screenSelector = selector
        screenDebounce = debounce
    }

    func resolveLayout() -> ScreenLayout { layoutToReturn }
}

// MARK: - Tests

@Suite("AppPresenter")
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

        let deadline = ContinuousClock.now + .seconds(1)
        while presenter.layout.windowFrame != expected.windowFrame, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

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
        let deadline1 = ContinuousClock.now + .seconds(1)
        while presenter.layout.windowFrame != initial.windowFrame, ContinuousClock.now < deadline1 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(presenter.layout.windowFrame == initial.windowFrame)

        interactor.layoutToReturn = updated
        interactor.changes.send(())

        let deadline2 = ContinuousClock.now + .seconds(1)
        while presenter.layout.windowFrame != updated.windowFrame, ContinuousClock.now < deadline2 {
            try? await Task.sleep(for: .milliseconds(10))
        }

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

        let deadline = ContinuousClock.now + .seconds(2)
        while presenter.layout.windowFrame != updated.windowFrame, ContinuousClock.now < deadline {
            await Task.yield()
        }

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

        let deadline = ContinuousClock.now + .seconds(1)
        while ripple.screenOrigin != CGPoint(x: 100, y: 40), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
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
        let deadline1 = ContinuousClock.now + .seconds(1)
        while ripple.screenOrigin != CGPoint(x: 0, y: 40), ContinuousClock.now < deadline1 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(ripple.screenOrigin == CGPoint(x: 0, y: 40))

        interactor.layoutToReturn = updated
        interactor.changes.send(())

        let deadline2 = ContinuousClock.now + .seconds(1)
        while ripple.screenOrigin != CGPoint(x: 1920, y: 40), ContinuousClock.now < deadline2 {
            try? await Task.sleep(for: .milliseconds(10))
        }
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
            var count = 0
        }
        let counter = Counter()

        presenter.start()
        // Wait for initial layout to flush
        let warm = ContinuousClock.now + .seconds(1)
        while presenter.layout.windowFrame != first.windowFrame, ContinuousClock.now < warm {
            try? await Task.sleep(for: .milliseconds(10))
        }
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

        // Give the DispatchQueue.main scheduling time to flush (CI load varies).
        let deadline = ContinuousClock.now + .seconds(3)
        while counter.count < 3, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
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
        let warm = ContinuousClock.now + .seconds(1)
        while presenter.layout.windowFrame != initial.windowFrame, ContinuousClock.now < warm {
            try? await Task.sleep(for: .milliseconds(10))
        }
        presenter.stop()

        interactor.layoutToReturn = updated
        interactor.changes.send(())

        // Give the publisher a chance to propagate; layout should stay at initial.
        try? await Task.sleep(for: .milliseconds(100))
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
        await waitUntil { presenter.layout.windowFrame == initial.windowFrame }

        // A config reload changed the screen selector — the interactor now resolves
        // a different display. The ping must re-resolve without a restart.
        screen.layoutToReturn = updated
        config.fire()
        await flushMainQueue()
        await waitUntil { presenter.layout.windowFrame == updated.windowFrame }

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
        await waitUntil { presenter.layout.windowFrame == initial.windowFrame }

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
        await waitUntil { presenter.layout.windowFrame == polled.windowFrame }

        #expect(presenter.layout.windowFrame == polled.windowFrame)
        presenter.stop()
    }
}
