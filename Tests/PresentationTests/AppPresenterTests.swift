import CoreGraphics
import Dependencies
import Domain
import Testing

@testable import Presentation

// MARK: - Stub

private struct StubScreenInteractor: ScreenInteractor, @unchecked Sendable {
    var screenSelector: ScreenSelector = .main
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
}
