import CoreGraphics
import Dependencies
import Domain
import Testing

@testable import ScreenInteractor

// MARK: - Stubs

private struct StubConfigUseCase: ConfigUseCase, Sendable {
    var style: AppStyle = .init()
    var appStyle: AppStyle { style }
    func template(format: ConfigFormat) -> String? { nil }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { "" }
    var existingConfigPath: String? { nil }
}

private struct StubScreenProvider: ScreenProvider {
    var screens: [ScreenInfo] = []
    var mainScreen: ScreenInfo? = nil
    var occupancyHandler: @Sendable (ScreenInfo) -> Double = { _ in 0 }

    func windowOccupancy(for screen: ScreenInfo) -> Double {
        occupancyHandler(screen)
    }
}

private let largeScreen = ScreenInfo(
    frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
    visibleFrame: CGRect(x: 0, y: 25, width: 1920, height: 1055)
)
private let smallScreen = ScreenInfo(
    frame: CGRect(x: 1920, y: 0, width: 1280, height: 720),
    visibleFrame: CGRect(x: 1920, y: 25, width: 1280, height: 695)
)
private let twoScreens = [largeScreen, smallScreen]

// MARK: - Tests

@Suite("ScreenInteractor")
struct ScreenInteractorImplTests {

    @Suite("screenSelector")
    struct ScreenSelectorTests {
        @Test("default screenSelector is .main")
        func defaultIsMain() {
            let interactor = withDependencies {
                $0.configUseCase = StubConfigUseCase()
                $0.screenProvider = StubScreenProvider()
            } operation: {
                ScreenInteractorImpl()
            }
            #expect(interactor.screenSelector == .main)
        }

        @Test("screenSelector reflects config value")
        func reflectsConfig() {
            let interactor = withDependencies {
                $0.configUseCase = StubConfigUseCase(style: AppStyle(screen: .largest))
                $0.screenProvider = StubScreenProvider()
            } operation: {
                ScreenInteractorImpl()
            }
            #expect(interactor.screenSelector == .largest)
        }
    }

    @Suite("resolveLayout")
    struct ResolveLayoutTests {
        @Test("empty screens returns zero layout")
        func emptyScreens() {
            let interactor = withDependencies {
                $0.configUseCase = StubConfigUseCase()
                $0.screenProvider = StubScreenProvider(screens: [])
            } operation: {
                ScreenInteractorImpl()
            }
            let layout = interactor.resolveLayout()
            #expect(layout.windowFrame == .zero)
        }

        @Test(".main selector uses mainScreen")
        func mainSelector() {
            let interactor = withDependencies {
                $0.configUseCase = StubConfigUseCase(style: AppStyle(screen: .main))
                $0.screenProvider = StubScreenProvider(screens: twoScreens, mainScreen: smallScreen)
            } operation: {
                ScreenInteractorImpl()
            }
            let layout = interactor.resolveLayout()
            #expect(layout.windowFrame == smallScreen.frame)
        }

        @Test(".main falls back to first screen when mainScreen is nil")
        func mainFallback() {
            let interactor = withDependencies {
                $0.configUseCase = StubConfigUseCase(style: AppStyle(screen: .main))
                $0.screenProvider = StubScreenProvider(screens: twoScreens, mainScreen: nil)
            } operation: {
                ScreenInteractorImpl()
            }
            let layout = interactor.resolveLayout()
            #expect(layout.windowFrame == largeScreen.frame)
        }

        @Test(".primary selector uses first screen")
        func primarySelector() {
            let interactor = withDependencies {
                $0.configUseCase = StubConfigUseCase(style: AppStyle(screen: .primary))
                $0.screenProvider = StubScreenProvider(screens: twoScreens)
            } operation: {
                ScreenInteractorImpl()
            }
            let layout = interactor.resolveLayout()
            #expect(layout.windowFrame == largeScreen.frame)
        }

        @Test(".index selects correct screen")
        func indexSelector() {
            let interactor = withDependencies {
                $0.configUseCase = StubConfigUseCase(style: AppStyle(screen: .index(1)))
                $0.screenProvider = StubScreenProvider(screens: twoScreens)
            } operation: {
                ScreenInteractorImpl()
            }
            let layout = interactor.resolveLayout()
            #expect(layout.windowFrame == smallScreen.frame)
        }

        @Test(".index out of range falls back to first screen")
        func indexOutOfRange() {
            let interactor = withDependencies {
                $0.configUseCase = StubConfigUseCase(style: AppStyle(screen: .index(999)))
                $0.screenProvider = StubScreenProvider(screens: twoScreens)
            } operation: {
                ScreenInteractorImpl()
            }
            let layout = interactor.resolveLayout()
            #expect(layout.windowFrame == largeScreen.frame)
        }

        @Test(".index negative falls back to first screen")
        func indexNegative() {
            let interactor = withDependencies {
                $0.configUseCase = StubConfigUseCase(style: AppStyle(screen: .index(-1)))
                $0.screenProvider = StubScreenProvider(screens: twoScreens)
            } operation: {
                ScreenInteractorImpl()
            }
            let layout = interactor.resolveLayout()
            #expect(layout.windowFrame == largeScreen.frame)
        }

        @Test(".smallest selector picks smallest by area")
        func smallestSelector() {
            let interactor = withDependencies {
                $0.configUseCase = StubConfigUseCase(style: AppStyle(screen: .smallest))
                $0.screenProvider = StubScreenProvider(screens: twoScreens)
            } operation: {
                ScreenInteractorImpl()
            }
            let layout = interactor.resolveLayout()
            #expect(layout.windowFrame == smallScreen.frame)
        }

        @Test(".largest selector picks largest by area")
        func largestSelector() {
            let interactor = withDependencies {
                $0.configUseCase = StubConfigUseCase(style: AppStyle(screen: .largest))
                $0.screenProvider = StubScreenProvider(screens: twoScreens)
            } operation: {
                ScreenInteractorImpl()
            }
            let layout = interactor.resolveLayout()
            #expect(layout.windowFrame == largeScreen.frame)
        }

        @Test("hostingFrame is computed from visible frame offset")
        func hostingFrameComputed() {
            let interactor = withDependencies {
                $0.configUseCase = StubConfigUseCase(style: AppStyle(screen: .primary))
                $0.screenProvider = StubScreenProvider(screens: [largeScreen])
            } operation: {
                ScreenInteractorImpl()
            }
            let layout = interactor.resolveLayout()
            #expect(layout.hostingFrame.origin.x == 0)
            #expect(layout.hostingFrame.origin.y == 25)
            #expect(layout.hostingFrame.width == 1920)
            #expect(layout.hostingFrame.height == 1055)
        }

        @Test("screenOrigin reflects visible frame origin")
        func screenOriginFromVisibleFrame() {
            let interactor = withDependencies {
                $0.configUseCase = StubConfigUseCase(style: AppStyle(screen: .index(1)))
                $0.screenProvider = StubScreenProvider(screens: twoScreens)
            } operation: {
                ScreenInteractorImpl()
            }
            let layout = interactor.resolveLayout()
            #expect(layout.screenOrigin.x == 1920)
            #expect(layout.screenOrigin.y == 25)
        }

        @Test(".vacant selector picks screen with least window coverage")
        func vacantSelector() {
            let interactor = withDependencies {
                $0.configUseCase = StubConfigUseCase(style: AppStyle(screen: .vacant))
                $0.screenProvider = StubScreenProvider(
                    screens: twoScreens,
                    occupancyHandler: { $0.frame == largeScreen.frame ? 0.7 : 0.1 }
                )
            } operation: {
                ScreenInteractorImpl()
            }
            let layout = interactor.resolveLayout()
            #expect(layout.windowFrame == smallScreen.frame)
        }

        @Test(".vacant prefers first when all screens equally occupied")
        func vacantEqualOccupancy() {
            let interactor = withDependencies {
                $0.configUseCase = StubConfigUseCase(style: AppStyle(screen: .vacant))
                $0.screenProvider = StubScreenProvider(screens: twoScreens)
            } operation: {
                ScreenInteractorImpl()
            }
            let layout = interactor.resolveLayout()
            #expect(layout.windowFrame == largeScreen.frame)
        }

        @Test(".vacant with single screen returns that screen")
        func vacantSingleScreen() {
            let interactor = withDependencies {
                $0.configUseCase = StubConfigUseCase(style: AppStyle(screen: .vacant))
                $0.screenProvider = StubScreenProvider(
                    screens: [smallScreen],
                    occupancyHandler: { _ in 0.8 }
                )
            } operation: {
                ScreenInteractorImpl()
            }
            let layout = interactor.resolveLayout()
            #expect(layout.windowFrame == smallScreen.frame)
        }

        @Test("screenDebounce reflects config value")
        func screenDebounceFromConfig() {
            let interactor = withDependencies {
                $0.configUseCase = StubConfigUseCase(style: AppStyle(screenDebounce: 10))
                $0.screenProvider = StubScreenProvider()
            } operation: {
                ScreenInteractorImpl()
            }
            #expect(interactor.screenDebounce == 10)
        }
    }
}
