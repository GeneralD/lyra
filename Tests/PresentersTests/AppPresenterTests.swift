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

    func resolveLayout() -> ScreenLayout { layoutToReturn }
}

// MARK: - Tests

@Suite("AppPresenter")
struct AppPresenterTests {

    @MainActor
    @Test("start() sets layout from ScreenInteractor")
    func startSetsLayout() {
        let expected = ScreenLayout(
            windowFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            hostingFrame: CGRect(x: 0, y: 0, width: 1920, height: 1040),
            screenOrigin: CGPoint(x: 0, y: 40)
        )

        withDependencies {
            $0.screenInteractor = StubScreenInteractor(layoutToReturn: expected)
        } operation: {
            let presenter = AppPresenter()
            presenter.start()

            #expect(presenter.layout.windowFrame == expected.windowFrame)
            #expect(presenter.layout.hostingFrame == expected.hostingFrame)
            #expect(presenter.layout.screenOrigin == expected.screenOrigin)
        }
    }

    @MainActor
    @Test("recalculateLayout() updates layout with new values")
    func recalculateLayoutUpdates() {
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

        // Use a mutable reference so we can change the return value mid-test
        final class MutableInteractor: ScreenInteractor, @unchecked Sendable {
            var screenSelector: ScreenSelector = .main
            var screenDebounce: Double = 5
            var layoutToReturn: ScreenLayout
            init(layout: ScreenLayout) { layoutToReturn = layout }
            func resolveLayout() -> ScreenLayout { layoutToReturn }
        }

        let interactor = MutableInteractor(layout: initial)

        withDependencies {
            $0.screenInteractor = interactor
        } operation: {
            let presenter = AppPresenter()
            presenter.start()
            #expect(presenter.layout.windowFrame == initial.windowFrame)

            // Simulate screen change
            interactor.layoutToReturn = updated
            presenter.recalculateLayout()

            #expect(presenter.layout.windowFrame == updated.windowFrame)
            #expect(presenter.layout.hostingFrame == updated.hostingFrame)
        }
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

        final class MutableInteractor: ScreenInteractor, @unchecked Sendable {
            var screenSelector: ScreenSelector = .vacant
            var screenDebounce: Double = 1
            var layoutToReturn: ScreenLayout
            init(layout: ScreenLayout) { layoutToReturn = layout }
            func resolveLayout() -> ScreenLayout { layoutToReturn }
        }

        let interactor = MutableInteractor(layout: initial)
        let presenter = withDependencies {
            $0.screenInteractor = interactor
            $0.continuousClock = ImmediateClock()
        } operation: {
            AppPresenter()
        }

        presenter.start()
        #expect(presenter.layout.windowFrame == initial.windowFrame)

        interactor.layoutToReturn = updated

        let deadline = ContinuousClock.now + .seconds(3)
        while presenter.layout.windowFrame != updated.windowFrame, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
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
            $0.continuousClock = ImmediateClock()
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

        final class MutableInteractor: ScreenInteractor, @unchecked Sendable {
            var screenSelector: ScreenSelector = .main
            var screenDebounce: Double = 5
            var layoutToReturn: ScreenLayout
            init(layout: ScreenLayout) { layoutToReturn = layout }
            func resolveLayout() -> ScreenLayout { layoutToReturn }
        }

        let interactor = MutableInteractor(layout: layout)
        let (presenter, ripple) = withDependencies {
            $0.screenInteractor = interactor
        } operation: {
            (AppPresenter(), RipplePresenter())
        }

        presenter.bind(ripplePresenter: ripple)
        presenter.start()

        // screenOrigin (100, 40), size 1920x1040 → ripple rect matches
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

        final class MutableInteractor: ScreenInteractor, @unchecked Sendable {
            var screenSelector: ScreenSelector = .main
            var screenDebounce: Double = 5
            var layoutToReturn: ScreenLayout
            init(layout: ScreenLayout) { layoutToReturn = layout }
            func resolveLayout() -> ScreenLayout { layoutToReturn }
        }

        let interactor = MutableInteractor(layout: initial)
        let (presenter, ripple) = withDependencies {
            $0.screenInteractor = interactor
        } operation: {
            (AppPresenter(), RipplePresenter())
        }

        presenter.bind(ripplePresenter: ripple)
        presenter.start()
        #expect(ripple.screenOrigin == CGPoint(x: 0, y: 40))

        interactor.layoutToReturn = updated
        presenter.recalculateLayout()

        #expect(ripple.screenOrigin == CGPoint(x: 1920, y: 40))
    }

    @MainActor
    @Test("onWindowFrameChange fires only when windowFrame actually changes")
    func onWindowFrameChangeDedups() async {
        let first = ScreenLayout(windowFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let sameFrame = ScreenLayout(
            windowFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            hostingFrame: CGRect(x: 0, y: 0, width: 1920, height: 1040)
        )
        let different = ScreenLayout(windowFrame: CGRect(x: 0, y: 0, width: 2560, height: 1440))

        final class MutableInteractor: ScreenInteractor, @unchecked Sendable {
            var screenSelector: ScreenSelector = .main
            var screenDebounce: Double = 5
            var layoutToReturn: ScreenLayout
            init(layout: ScreenLayout) { layoutToReturn = layout }
            func resolveLayout() -> ScreenLayout { layoutToReturn }
        }

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
        // Subscribe after start so the current layout is dropped.
        presenter.onWindowFrameChange { _ in counter.count += 1 }

        // Same windowFrame (different hostingFrame) → deduped.
        interactor.layoutToReturn = sameFrame
        presenter.recalculateLayout()

        // Different windowFrame → fires.
        interactor.layoutToReturn = different
        presenter.recalculateLayout()

        // Give the DispatchQueue.main scheduling a tick to flush.
        let deadline = ContinuousClock.now + .seconds(1)
        while counter.count < 1, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(counter.count == 1)
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
}
