import Dependencies
import Domain
import Testing

@testable import ScreenInteractor

// MARK: - Stub

private struct StubConfigUseCase: ConfigUseCase, Sendable {
    var style: AppStyle = .init()
    var appStyle: AppStyle { style }
    func template(format: ConfigFormat) -> String? { nil }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { "" }
    var existingConfigPath: String? { nil }
}

// MARK: - Tests

@Suite("ScreenInteractor")
struct ScreenInteractorImplTests {

    @MainActor
    @Test("resolveLayout returns non-zero window frame from real screen")
    func resolveLayoutReturnsNonZeroFrame() {
        let interactor = withDependencies {
            $0.configUseCase = StubConfigUseCase()
        } operation: {
            ScreenInteractorImpl()
        }

        let layout = interactor.resolveLayout()
        #expect(layout.windowFrame.width > 0)
        #expect(layout.windowFrame.height > 0)
    }

    @MainActor
    @Test("resolveLayout hostingFrame fits within windowFrame")
    func hostingFrameFitsInWindow() {
        let interactor = withDependencies {
            $0.configUseCase = StubConfigUseCase()
        } operation: {
            ScreenInteractorImpl()
        }

        let layout = interactor.resolveLayout()
        #expect(layout.hostingFrame.width <= layout.windowFrame.width)
        #expect(layout.hostingFrame.height <= layout.windowFrame.height)
    }

    @MainActor
    @Test("default screenSelector is .main")
    func defaultScreenSelectorIsMain() {
        let interactor = withDependencies {
            $0.configUseCase = StubConfigUseCase()
        } operation: {
            ScreenInteractorImpl()
        }

        #expect(interactor.screenSelector == .main)
    }

    @MainActor
    @Test("screenSelector reflects config value")
    func screenSelectorReflectsConfig() {
        let style = AppStyle(screen: .largest)
        let interactor = withDependencies {
            $0.configUseCase = StubConfigUseCase(style: style)
        } operation: {
            ScreenInteractorImpl()
        }

        #expect(interactor.screenSelector == .largest)
    }

    @MainActor
    @Test("out-of-range index falls back to valid screen — no crash")
    func outOfRangeIndexDoesNotCrash() {
        let style = AppStyle(screen: .index(999))
        let interactor = withDependencies {
            $0.configUseCase = StubConfigUseCase(style: style)
        } operation: {
            ScreenInteractorImpl()
        }

        let layout = interactor.resolveLayout()
        #expect(layout.windowFrame.width > 0, "fallback screen should have non-zero width")
    }

    @MainActor
    @Test("primary selector resolves to first screen")
    func primarySelector() {
        let style = AppStyle(screen: .primary)
        let interactor = withDependencies {
            $0.configUseCase = StubConfigUseCase(style: style)
        } operation: {
            ScreenInteractorImpl()
        }

        let layout = interactor.resolveLayout()
        #expect(layout.windowFrame.width > 0)
    }

    @MainActor
    @Test("smallest selector resolves without crash")
    func smallestSelector() {
        let style = AppStyle(screen: .smallest)
        let interactor = withDependencies {
            $0.configUseCase = StubConfigUseCase(style: style)
        } operation: {
            ScreenInteractorImpl()
        }

        let layout = interactor.resolveLayout()
        #expect(layout.windowFrame.width > 0)
    }

    @MainActor
    @Test("index 0 resolves to first screen")
    func indexZero() {
        let style = AppStyle(screen: .index(0))
        let interactor = withDependencies {
            $0.configUseCase = StubConfigUseCase(style: style)
        } operation: {
            ScreenInteractorImpl()
        }

        let layout = interactor.resolveLayout()
        #expect(layout.windowFrame.width > 0)
    }
}
