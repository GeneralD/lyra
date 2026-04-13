import AppKit
import Dependencies
import Domain
import Presenters
import SwiftUI
import Testing
import Views

@testable import AppRouter

@MainActor
private func waitUntil(
    timeout: Duration = .seconds(3),
    condition: @escaping @MainActor () -> Bool
) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

@Suite("AppLaunchEnvironment")
struct AppLaunchEnvironmentTests {
    @Test("parses UI test launch environment and lyrics lines")
    func parsesEnvironment() {
        let environment = AppLaunchEnvironment(
            environment: [
                .uiTestMode: "true",
                .lyricsTitle: "Test Song",
                .lyricsArtist: "Test Artist",
                .lyricsLines: "Line 1\nLine 2\n\nLine 3",
            ]
        )

        #expect(environment.isUITestMode)
        #expect(environment.title == "Test Song")
        #expect(environment.artist == "Test Artist")
        #expect(environment.lyricsLines == ["Line 1", "Line 2", "Line 3"])
    }

    @Test("uses stable defaults when environment is missing")
    func defaults() {
        let environment = AppLaunchEnvironment(environment: [:])

        #expect(!environment.isUITestMode)
        #expect(environment.title == "UI Test Song")
        #expect(environment.artist == "UI Test Artist")
        #expect(environment.lyricsLines == ["First UI test lyric", "Second UI test lyric"])
    }

    @Test("falls back to default lyrics when parsed lines are empty")
    func defaultsForEmptyLyrics() {
        let environment = AppLaunchEnvironment(
            environment: [
                .uiTestMode: "on",
                .lyricsLines: " \n \n",
            ]
        )

        #expect(environment.isUITestMode)
        #expect(environment.lyricsLines == ["First UI test lyric", "Second UI test lyric"])
    }
}

@MainActor
@Suite("AppDependencyBootstrap")
struct AppDependencyBootstrapTests {
    @Test("injects fixture track data for presenters in UI test mode")
    func injectsFixtureTrackData() async {
        let bootstrap = AppDependencyBootstrap(
            launchEnvironment: .init(
                environment: [
                    .uiTestMode: "1",
                    .lyricsTitle: "Bootstrap Song",
                    .lyricsArtist: "Bootstrap Artist",
                    .lyricsLines: "Alpha\nBeta",
                ]
            )
        )

        let headerPresenter = withDependencies {
            bootstrap.apply(to: &$0)
        } operation: {
            HeaderPresenter()
        }
        let lyricsPresenter = withDependencies {
            bootstrap.apply(to: &$0)
        } operation: {
            LyricsPresenter()
        }

        headerPresenter.start()
        lyricsPresenter.start()
        await waitUntil {
            headerPresenter.displayTitle == "Bootstrap Song"
                && headerPresenter.displayArtist == "Bootstrap Artist"
                && lyricsPresenter.displayLyricLines == ["Alpha", "Beta"]
                && lyricsPresenter.lyricsState == .success(.plain(["Alpha", "Beta"]))
        }

        #expect(headerPresenter.displayTitle == "Bootstrap Song")
        #expect(headerPresenter.displayArtist == "Bootstrap Artist")
        #expect(lyricsPresenter.displayLyricLines == ["Alpha", "Beta"])
        #expect(lyricsPresenter.lyricsState == .success(.plain(["Alpha", "Beta"])))
    }

    @Test("injects screen and wallpaper fixtures for app bootstrap")
    func injectsLayoutAndWallpaperFixtures() async throws {
        let bootstrap = AppDependencyBootstrap(
            launchEnvironment: .init(
                environment: [
                    .uiTestMode: "true",
                    .lyricsTitle: "Layout Song",
                    .lyricsArtist: "Layout Artist",
                ]
            )
        )

        let screenSelector = withDependencies {
            bootstrap.apply(to: &$0)
        } operation: {
            @Dependency(\.screenInteractor) var screenInteractor
            return screenInteractor.screenSelector
        }

        let layout = withDependencies {
            bootstrap.apply(to: &$0)
        } operation: {
            let presenter = AppPresenter()
            presenter.start()
            return presenter.layout
        }

        let wallpaper = try await withDependencies {
            bootstrap.apply(to: &$0)
        } operation: {
            @Dependency(\.wallpaperInteractor) var wallpaperInteractor
            return try await wallpaperInteractor.resolveWallpaper()
        }

        let ripplePresenter = withDependencies {
            bootstrap.apply(to: &$0)
        } operation: {
            RipplePresenter()
        }
        ripplePresenter.start()

        #expect(screenSelector == .main)
        #expect(layout.windowFrame == CGRect(x: 0, y: 0, width: 1280, height: 720))
        #expect(layout.hostingFrame == CGRect(x: 0, y: 0, width: 1280, height: 720))
        #expect(layout.screenOrigin == .zero)
        #expect(wallpaper.url == nil)
        #expect(wallpaper.start == nil)
        #expect(wallpaper.end == nil)
        #expect(ripplePresenter.isEnabled == false)
        #expect(ripplePresenter.rippleState != nil)
    }
}

@MainActor
@Suite("AppRouter")
struct AppRouterTests {
    @Test("public init uses default factories")
    func publicInit() {
        let router = AppRouter()
        #expect(!hasValue(named: "appWindow", from: router))
    }

    @Test("start applies bootstrap fixture graph and stop tears it down")
    func startAndStop() async {
        let window = SpyWindow()
        let driver = SpyDisplayLinkDriver()

        let router = AppRouter(
            launchEnvironment: .init(
                environment: [
                    .uiTestMode: "true",
                    .lyricsTitle: "Router Song",
                    .lyricsArtist: "Router Artist",
                    .lyricsLines: "One\nTwo",
                ]
            ),
            windowFactory: { _, _, _, _, _ in window },
            displayLinkDriverFactory: { onFrame in
                driver.onFrame = onFrame
                return driver
            }
        )

        router.start()
        await waitUntil {
            let headerPresenter: HeaderPresenter? = value(named: "headerPresenter", from: router)
            let lyricsPresenter: LyricsPresenter? = value(named: "lyricsPresenter", from: router)
            return headerPresenter?.displayTitle == "Router Song"
                && headerPresenter?.displayArtist == "Router Artist"
                && lyricsPresenter?.displayLyricLines == ["One", "Two"]
        }

        let appPresenter: AppPresenter? = value(named: "appPresenter", from: router)
        let headerPresenter: HeaderPresenter? = value(named: "headerPresenter", from: router)
        let lyricsPresenter: LyricsPresenter? = value(named: "lyricsPresenter", from: router)
        let wallpaperPresenter: WallpaperPresenter? = value(named: "wallpaperPresenter", from: router)
        let ripplePresenter: RipplePresenter? = value(named: "ripplePresenter", from: router)
        let appWindow: AnyObject? = value(named: "appWindow", from: router)

        #expect(appPresenter?.layout.windowFrame == CGRect(x: 0, y: 0, width: 1280, height: 720))
        #expect(headerPresenter?.displayTitle == "Router Song")
        #expect(headerPresenter?.displayArtist == "Router Artist")
        #expect(lyricsPresenter?.displayLyricLines == ["One", "Two"])
        #expect(wallpaperPresenter != nil)
        #expect(ripplePresenter != nil)
        #expect(appWindow === window)
        #expect(driver.startCallCount == 1)

        driver.fire()

        router.stop()

        #expect(!hasValue(named: "appWindow", from: router))
        #expect(window.orderOutCallCount == 1)
        #expect(window.closeCallCount == 1)
        #expect(driver.stopCallCount == 1)
    }

    @Test("start ignores duplicate calls and stop clears router state")
    func startIsIdempotent() {
        let window = SpyWindow()
        let driver = SpyDisplayLinkDriver()

        let router = AppRouter(
            launchEnvironment: .init(environment: [.uiTestMode: "true"]),
            windowFactory: { _, _, _, _, _ in window },
            displayLinkDriverFactory: { onFrame in
                driver.onFrame = onFrame
                return driver
            }
        )

        router.start()
        router.start()

        #expect(driver.startCallCount == 1)
        #expect(value(named: "appPresenter", from: router) as AppPresenter? != nil)

        router.stop()

        #expect(driver.stopCallCount == 1)
        #expect(!hasValue(named: "appPresenter", from: router))
        #expect(!hasValue(named: "headerPresenter", from: router))
        #expect(!hasValue(named: "lyricsPresenter", from: router))
        #expect(!hasValue(named: "wallpaperPresenter", from: router))
        #expect(!hasValue(named: "ripplePresenter", from: router))
        #expect(!hasValue(named: "displayLinkDriver", from: router))
        #expect(!hasValue(named: "appWindow", from: router))
    }

    private final class SpyWindow: AppWindowing {
        var orderOutCallCount = 0
        var closeCallCount = 0

        func orderOut(_ sender: Any?) {
            orderOutCallCount += 1
        }

        func close() {
            closeCallCount += 1
        }
    }

    private final class SpyDisplayLinkDriver: DisplayLinkDriving {
        var startCallCount = 0
        var stopCallCount = 0
        var onFrame: (@MainActor () -> Void)?

        func start(in window: any AppWindowing) {
            startCallCount += 1
        }

        func stop() {
            stopCallCount += 1
        }

        func fire() {
            onFrame?()
        }
    }

    private func value<T>(named name: String, from object: Any) -> T? {
        guard
            let storedValue = Mirror(reflecting: object).children
                .first(where: { $0.label == name })?
                .value
        else { return nil }

        return unwrap(storedValue) as? T
    }

    private func unwrap(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return value }
        return mirror.children.first?.value
    }

    private func hasValue(named name: String, from object: Any) -> Bool {
        guard
            let storedValue = Mirror(reflecting: object).children
                .first(where: { $0.label == name })?
                .value
        else { return false }

        let mirror = Mirror(reflecting: storedValue)
        guard mirror.displayStyle == .optional else { return true }
        return mirror.children.first != nil
    }
}

@MainActor
@Suite("Accessibility hooks")
struct AccessibilityHooksTests {
    private struct EnabledRippleWallpaperInteractor: WallpaperInteractor {
        var rippleConfig: RippleStyle { .init(enabled: true) }
        func resolveWallpaper() async throws -> WallpaperState { .init() }
    }

    @Test("renders header, lyrics, overlay, and ripple test surfaces")
    func rendersViews() async {
        let bootstrap = AppDependencyBootstrap(
            launchEnvironment: .init(
                environment: [
                    .uiTestMode: "true",
                    .lyricsTitle: "Accessible Song",
                    .lyricsArtist: "Accessible Artist",
                    .lyricsLines: "First\nSecond",
                ]
            )
        )

        let headerPresenter = withDependencies {
            bootstrap.apply(to: &$0)
        } operation: {
            HeaderPresenter()
        }
        let lyricsPresenter = withDependencies {
            bootstrap.apply(to: &$0)
        } operation: {
            LyricsPresenter()
        }
        let overlayRipplePresenter = withDependencies {
            bootstrap.apply(to: &$0)
        } operation: {
            RipplePresenter()
        }
        let ripplePresenter = withDependencies {
            $0.wallpaperInteractor = EnabledRippleWallpaperInteractor()
        } operation: {
            RipplePresenter()
        }

        headerPresenter.start()
        lyricsPresenter.start()
        overlayRipplePresenter.start()
        ripplePresenter.start()
        defer {
            ripplePresenter.stop()
            overlayRipplePresenter.stop()
            lyricsPresenter.stop()
            headerPresenter.stop()
        }
        await waitUntil {
            headerPresenter.displayTitle == "Accessible Song"
                && lyricsPresenter.displayLyricLines == ["First", "Second"]
        }

        render(HeaderView(presenter: headerPresenter), size: CGSize(width: 600, height: 120))
        render(LyricsColumnView(presenter: lyricsPresenter), size: CGSize(width: 600, height: 300))
        render(
            OverlayContentView(
                headerPresenter: headerPresenter,
                lyricsPresenter: lyricsPresenter,
                ripplePresenter: overlayRipplePresenter
            ),
            size: CGSize(width: 800, height: 500)
        )
        render(RippleView(presenter: ripplePresenter), size: CGSize(width: 400, height: 300))

        #expect(headerPresenter.displayTitle == "Accessible Song")
        #expect(lyricsPresenter.displayLyricLines == ["First", "Second"])
        #expect(ripplePresenter.rippleState != nil)
    }

    private func render<Content: View>(_ view: Content, size: CGSize) {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()
        _ = hostingView.fittingSize
    }
}
