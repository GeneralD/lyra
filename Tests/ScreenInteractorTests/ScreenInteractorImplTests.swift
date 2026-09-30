import AppKit
import Combine
import CoreGraphics
import Dependencies
import Domain
import TestSupport
import Testing

@testable import ScreenInteractor

// MARK: - Stubs

private struct StubConfigUseCase: ConfigUseCase, Sendable {
    var style: AppStyle = .init()
    var appStyle: AppStyle { style }
    func reload() -> ConfigReloadOutcome { .updated(appStyle) }
    func template(format: ConfigFormat) -> String? { nil }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { "" }
    var existingConfigPath: String? { nil }
}

private final class CountingScreenProvider: ScreenProvider, @unchecked Sendable {
    var screens: [ScreenInfo] = []
    var mainScreen: ScreenInfo? = nil
    var occupancyHandler: @Sendable (ScreenInfo) -> Double = { _ in 0 }
    var coverageHandler: @Sendable (ScreenInfo) -> Double = { _ in 0 }
    private(set) var occupancyCallCount = 0
    private(set) var coverageCallCount = 0

    func windowOccupancy(for screen: ScreenInfo) -> Double {
        occupancyCallCount += 1
        return occupancyHandler(screen)
    }

    func windowCoverage(for screen: ScreenInfo) -> Double {
        coverageCallCount += 1
        return coverageHandler(screen)
    }
}

private struct StubScreenProvider: ScreenProvider {
    var screens: [ScreenInfo] = []
    var mainScreen: ScreenInfo? = nil
    var occupancyHandler: @Sendable (ScreenInfo) -> Double = { _ in 0 }
    var coverageHandler: @Sendable (ScreenInfo) -> Double = { _ in 0 }

    func windowOccupancy(for screen: ScreenInfo) -> Double {
        occupancyHandler(screen)
    }

    func windowCoverage(for screen: ScreenInfo) -> Double {
        coverageHandler(screen)
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

        @Test(".vacant calls windowOccupancy exactly N times for N screens (regression: #279)")
        func vacantOccupancyCallCount() {
            let provider = CountingScreenProvider()
            provider.screens = twoScreens
            provider.occupancyHandler = { $0.frame == largeScreen.frame ? 0.7 : 0.1 }

            let interactor = withDependencies {
                $0.configUseCase = StubConfigUseCase(style: AppStyle(screen: .vacant))
                $0.screenProvider = provider
            } operation: {
                ScreenInteractorImpl()
            }
            _ = interactor.resolveLayout()

            // CGWindowListCopyWindowInfo must be called exactly N times (once per screen),
            // not 2(N-1) times as with Array.min(by:) calling the comparator twice per comparison.
            #expect(provider.occupancyCallCount == twoScreens.count)
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

    @Suite("screenChanges", .timeLimit(.minutes(1)))
    struct ScreenChangesTests {
        @Test("emits when screen parameters change notification fires")
        func emitsOnNotification() async {
            let interactor = withDependencies {
                $0.configUseCase = StubConfigUseCase()
                $0.screenProvider = StubScreenProvider()
            } operation: {
                ScreenInteractorImpl()
            }

            let counter = Collector<Void>()
            let cancellable = interactor.screenChanges.sink { counter.append(()) }

            NotificationCenter.default.post(
                name: NSApplication.didChangeScreenParametersNotification, object: nil)

            await counter.waitForCount(1)

            #expect(counter.count >= 1)
            cancellable.cancel()
        }

        @Test(
            "emits when the window is moved or resized by the system (regression: #265)",
            arguments: [NSWindow.didMoveNotification, NSWindow.didResizeNotification]
        )
        func emitsOnWindowNotification(name: Notification.Name) async {
            let interactor = withDependencies {
                $0.configUseCase = StubConfigUseCase()
                $0.screenProvider = StubScreenProvider()
            } operation: {
                ScreenInteractorImpl()
            }

            let counter = Collector<Void>()
            let cancellable = interactor.screenChanges.sink { counter.append(()) }

            NotificationCenter.default.post(name: name, object: nil)

            await counter.waitForCount(1)

            #expect(counter.count >= 1)
            cancellable.cancel()
        }
    }

    @Suite("occlusionPauseEnabled")
    struct OcclusionPauseEnabledTests {
        @Test("reflects config value", arguments: [true, false])
        func reflectsConfig(enabled: Bool) {
            let interactor = withDependencies {
                $0.configUseCase = StubConfigUseCase(
                    style: AppStyle(occlusionPause: OcclusionPauseStyle(enabled: enabled))
                )
                $0.screenProvider = StubScreenProvider()
            } operation: {
                ScreenInteractorImpl()
            }
            #expect(interactor.occlusionPauseEnabled == enabled)
        }
    }

    @Suite("resolveState")
    struct ResolveStateTests {
        @Test("disabled occlusion pause never occludes, regardless of coverage")
        func disabledNeverOccludes() {
            let interactor = withDependencies {
                $0.configUseCase = StubConfigUseCase(
                    style: AppStyle(screen: .primary, occlusionPause: OcclusionPauseStyle(enabled: false, threshold: 0.5))
                )
                $0.screenProvider = StubScreenProvider(screens: [largeScreen], coverageHandler: { _ in 1.0 })
            } operation: {
                ScreenInteractorImpl()
            }
            let state = interactor.resolveState(previousScreen: nil, wasPaused: false)
            #expect(state.isOccluded == false)
        }

        @Test("enabled, not paused, coverage at or above threshold occludes")
        func enabledNotPausedAboveThreshold() {
            let interactor = withDependencies {
                $0.configUseCase = StubConfigUseCase(
                    style: AppStyle(screen: .primary, occlusionPause: OcclusionPauseStyle(enabled: true, threshold: 0.9))
                )
                $0.screenProvider = StubScreenProvider(screens: [largeScreen], coverageHandler: { _ in 0.9 })
            } operation: {
                ScreenInteractorImpl()
            }
            let state = interactor.resolveState(previousScreen: nil, wasPaused: false)
            #expect(state.isOccluded == true)
        }

        @Test("enabled, not paused, coverage below threshold does not occlude")
        func enabledNotPausedBelowThreshold() {
            let interactor = withDependencies {
                $0.configUseCase = StubConfigUseCase(
                    style: AppStyle(screen: .primary, occlusionPause: OcclusionPauseStyle(enabled: true, threshold: 0.9))
                )
                $0.screenProvider = StubScreenProvider(screens: [largeScreen], coverageHandler: { _ in 0.89 })
            } operation: {
                ScreenInteractorImpl()
            }
            let state = interactor.resolveState(previousScreen: nil, wasPaused: false)
            #expect(state.isOccluded == false)
        }

        @Test("while paused, coverage within the hysteresis band keeps occluding")
        func pausedWithinHysteresisStaysOccluded() {
            let interactor = withDependencies {
                $0.configUseCase = StubConfigUseCase(
                    style: AppStyle(screen: .primary, occlusionPause: OcclusionPauseStyle(enabled: true, threshold: 0.9))
                )
                $0.screenProvider = StubScreenProvider(screens: [largeScreen], coverageHandler: { _ in 0.85 })
            } operation: {
                ScreenInteractorImpl()
            }
            let state = interactor.resolveState(previousScreen: largeScreen, wasPaused: true)
            #expect(state.isOccluded == true)
        }

        @Test("while paused, coverage below the hysteresis band resumes")
        func pausedBelowHysteresisResumes() {
            let interactor = withDependencies {
                $0.configUseCase = StubConfigUseCase(
                    style: AppStyle(screen: .primary, occlusionPause: OcclusionPauseStyle(enabled: true, threshold: 0.9))
                )
                $0.screenProvider = StubScreenProvider(screens: [largeScreen], coverageHandler: { _ in 0.84 })
            } operation: {
                ScreenInteractorImpl()
            }
            let state = interactor.resolveState(previousScreen: largeScreen, wasPaused: true)
            #expect(state.isOccluded == false)
        }

        @Test("resolveState's layout matches resolveLayout()")
        func layoutMatchesResolveLayout() {
            let interactor = withDependencies {
                $0.configUseCase = StubConfigUseCase(
                    style: AppStyle(screen: .index(1), occlusionPause: OcclusionPauseStyle(enabled: true, threshold: 0.9))
                )
                $0.screenProvider = StubScreenProvider(screens: twoScreens, coverageHandler: { _ in 0.5 })
            } operation: {
                ScreenInteractorImpl()
            }
            let state = interactor.resolveState(previousScreen: nil, wasPaused: false)
            let layout = interactor.resolveLayout()
            #expect(state.layout == layout)
        }

        @Test(
            ".vacant + enabled calls windowOccupancy once per screen and windowCoverage exactly once, from a single resolveScreen() resolution"
        )
        func vacantEnabledCallCounts() {
            let provider = CountingScreenProvider()
            provider.screens = twoScreens
            provider.occupancyHandler = { $0.frame == largeScreen.frame ? 0.7 : 0.1 }
            provider.coverageHandler = { _ in 0.95 }

            let interactor = withDependencies {
                $0.configUseCase = StubConfigUseCase(
                    style: AppStyle(screen: .vacant, occlusionPause: OcclusionPauseStyle(enabled: true, threshold: 0.9))
                )
                $0.screenProvider = provider
            } operation: {
                ScreenInteractorImpl()
            }
            let state = interactor.resolveState(previousScreen: nil, wasPaused: false)

            // A single resolveScreen() call: windowOccupancy fires once per screen
            // (vacant selection, mirroring the #279 regression test), and
            // windowCoverage fires exactly once, for the resolved screen only.
            #expect(provider.occupancyCallCount == twoScreens.count)
            #expect(provider.coverageCallCount == 1)
            #expect(state.isOccluded == true)
        }

        @Test(".vacant + disabled never calls windowCoverage")
        func vacantDisabledSkipsCoverage() {
            let provider = CountingScreenProvider()
            provider.screens = twoScreens
            provider.occupancyHandler = { $0.frame == largeScreen.frame ? 0.7 : 0.1 }

            let interactor = withDependencies {
                $0.configUseCase = StubConfigUseCase(
                    style: AppStyle(screen: .vacant, occlusionPause: OcclusionPauseStyle(enabled: false, threshold: 0.9))
                )
                $0.screenProvider = provider
            } operation: {
                ScreenInteractorImpl()
            }
            let state = interactor.resolveState(previousScreen: nil, wasPaused: false)

            #expect(provider.coverageCallCount == 0)
            #expect(state.isOccluded == false)
        }

        @Test(
            ".vacant re-selecting a different screen does not inherit the previous screen's resume hysteresis (regression: #355)"
        )
        func vacantScreenSwitchDoesNotLeakHysteresis() {
            let provider = CountingScreenProvider()
            provider.screens = twoScreens
            // Tick 1: smallScreen is least occupied, so .vacant selects it.
            provider.occupancyHandler = { $0.frame == largeScreen.frame ? 0.9 : 0.1 }
            provider.coverageHandler = { _ in 0.95 }

            let interactor = withDependencies {
                $0.configUseCase = StubConfigUseCase(
                    style: AppStyle(screen: .vacant, occlusionPause: OcclusionPauseStyle(enabled: true, threshold: 0.9))
                )
                $0.screenProvider = provider
            } operation: {
                ScreenInteractorImpl()
            }

            let first = interactor.resolveState(previousScreen: nil, wasPaused: false)
            #expect(first.isOccluded == true)
            #expect(first.screen == smallScreen)

            // Tick 2: occupancy flips, so .vacant now selects largeScreen instead —
            // a screen resolveState never measured coverage on before. Its coverage
            // (0.87) is below the plain threshold (0.9) but within the *resume* side
            // hysteresis band (threshold - 0.05 = 0.85) that only means something for
            // the screen that earned it (smallScreen). Passing the previous screen
            // must stop that hysteresis from leaking onto largeScreen.
            provider.occupancyHandler = { $0.frame == largeScreen.frame ? 0.1 : 0.9 }
            provider.coverageHandler = { _ in 0.87 }

            let second = interactor.resolveState(previousScreen: first.screen, wasPaused: first.isOccluded)
            #expect(second.screen == largeScreen)
            #expect(second.isOccluded == false)
        }

        @Test(".vacant re-selecting the SAME screen still applies the resume hysteresis (regression: #355)")
        func vacantSameScreenStillAppliesHysteresis() {
            let provider = CountingScreenProvider()
            provider.screens = twoScreens
            // .vacant selects smallScreen on both ticks — occupancy never flips.
            provider.occupancyHandler = { $0.frame == largeScreen.frame ? 0.9 : 0.1 }
            provider.coverageHandler = { _ in 0.95 }

            let interactor = withDependencies {
                $0.configUseCase = StubConfigUseCase(
                    style: AppStyle(screen: .vacant, occlusionPause: OcclusionPauseStyle(enabled: true, threshold: 0.9))
                )
                $0.screenProvider = provider
            } operation: {
                ScreenInteractorImpl()
            }

            let first = interactor.resolveState(previousScreen: nil, wasPaused: false)
            #expect(first.isOccluded == true)
            #expect(first.screen == smallScreen)

            // Same screen resolved again; coverage (0.87) sits within the resume
            // hysteresis band (>= 0.85), so it must still be reported as occluded.
            provider.coverageHandler = { _ in 0.87 }
            let second = interactor.resolveState(previousScreen: first.screen, wasPaused: first.isOccluded)
            #expect(second.screen == smallScreen)
            #expect(second.isOccluded == true)
        }
    }
}
