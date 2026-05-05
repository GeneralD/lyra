import AppKit
import Testing

@testable import App

@MainActor
private final class SpyRouter: AppRouting {
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }
}

@MainActor
private final class SpyTerminationHandler: TerminationHandling {
    private(set) var installedHandler: (@MainActor () -> Void)?

    func install(onTermination: @escaping @MainActor () -> Void) {
        installedHandler = onTermination
    }
}

@MainActor
@Suite("AppDelegate")
struct AppDelegateTests {
    @Test("launch starts router and installs termination handler")
    func launchStartsRouter() {
        let router = SpyRouter()
        let terminationHandler = SpyTerminationHandler()
        let delegate = AppDelegate(
            routerFactory: { router },
            terminationHandler: terminationHandler
        )

        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )

        #expect(router.startCount == 1)
        #expect(router.stopCount == 0)
        #expect(terminationHandler.installedHandler != nil)
    }

    @Test("termination handler stops router")
    func terminationStopsRouter() throws {
        let router = SpyRouter()
        let terminationHandler = SpyTerminationHandler()
        let delegate = AppDelegate(
            routerFactory: { router },
            terminationHandler: terminationHandler
        )

        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )

        let installedHandler = try #require(terminationHandler.installedHandler)
        installedHandler()

        #expect(router.startCount == 1)
        #expect(router.stopCount == 1)
    }
}
