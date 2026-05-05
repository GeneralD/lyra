import AppKit
import Darwin
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
private final class SpyForegroundApplicationBackend: ForegroundApplicationBackend {
    private(set) var events: [String] = []
    private(set) var assignedDelegate: AnyObject?

    func setAccessoryActivationPolicy() {
        events.append("activation")
    }

    func setDelegate(_ delegate: any NSApplicationDelegate) {
        assignedDelegate = delegate as AnyObject
        events.append("delegate")
    }

    func run() {
        events.append("run")
    }
}

@MainActor
private final class SpyForegroundApplicationProcess: ForegroundApplicationProcess {
    private(set) var activationPolicies: [NSApplication.ActivationPolicy] = []
    private(set) var runCount = 0
    var delegate: (any NSApplicationDelegate)?

    @discardableResult
    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool {
        activationPolicies.append(activationPolicy)
        return true
    }

    func run() {
        runCount += 1
    }
}

private final class SpySignalSource: AppSignalSource {
    private(set) var resumeCount = 0
    private(set) var installedHandler: (() -> Void)?

    func setEventHandler(_ handler: @escaping () -> Void) {
        installedHandler = handler
    }

    func resume() {
        resumeCount += 1
    }
}

@MainActor
private final class SpySignalHandlingBackend: SignalHandlingBackend {
    private(set) var ignoredSignals: [Int32] = []
    private(set) var sourceSignals: [Int32] = []
    private(set) var sourceQueues: [DispatchQueue] = []
    private(set) var terminationStatuses: [Int32] = []
    private(set) var sources: [SpySignalSource] = []

    func ignoreSignal(_ signalType: Int32) {
        ignoredSignals.append(signalType)
    }

    func makeSignalSource(signal signalType: Int32, queue: DispatchQueue) -> any AppSignalSource {
        let source = SpySignalSource()
        sourceSignals.append(signalType)
        sourceQueues.append(queue)
        sources.append(source)
        return source
    }

    func terminateProcess(_ status: Int32) {
        terminationStatuses.append(status)
    }
}

private final class SpyApplicationDelegate: NSObject, NSApplicationDelegate {}

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

@MainActor
@Suite("ForegroundApplication")
struct ForegroundApplicationTests {
    @Test("runs accessory application through backend")
    func runAccessory() {
        let backend = SpyForegroundApplicationBackend()
        let delegate = SpyApplicationDelegate()

        ForegroundApplication.runAccessory(
            backend: backend,
            delegateFactory: { delegate }
        )

        #expect(backend.events == ["activation", "delegate", "run"])
        #expect(backend.assignedDelegate === delegate)
    }
}

@MainActor
@Suite("NSApplicationForegroundBackend")
struct NSApplicationForegroundBackendTests {
    @Test("forwards activation policy delegate and run to application process")
    func forwardsToApplicationProcess() {
        let application = SpyForegroundApplicationProcess()
        let delegate = SpyApplicationDelegate()
        let backend = NSApplicationForegroundBackend(application: application)

        backend.setAccessoryActivationPolicy()
        backend.setDelegate(delegate)
        backend.run()

        #expect(application.activationPolicies == [.accessory])
        #expect((application.delegate as AnyObject?) === delegate)
        #expect(application.runCount == 1)
    }
}

@MainActor
@Suite("SignalTerminationHandler")
struct SignalTerminationHandlerTests {
    @Test("installs ignored signal sources and resumes them")
    func install() {
        let backend = SpySignalHandlingBackend()
        let handler = SignalTerminationHandler(signals: [15, 2], backend: backend)
        var terminationCount = 0

        handler.install {
            terminationCount += 1
        }

        #expect(backend.ignoredSignals == [15, 2])
        #expect(backend.sourceSignals == [15, 2])
        #expect(backend.sourceQueues == [.main, .main])
        #expect(backend.sources.map(\.resumeCount) == [1, 1])
        #expect(backend.sources.allSatisfy { $0.installedHandler != nil })
        #expect(terminationCount == 0)
        #expect(backend.terminationStatuses.isEmpty)
    }

    @Test("signal event stops app before terminating process")
    func eventHandler() throws {
        let backend = SpySignalHandlingBackend()
        let handler = SignalTerminationHandler(signals: [15], backend: backend)
        var events: [String] = []

        handler.install {
            events.append("stop")
        }

        let installedHandler = try #require(backend.sources.first?.installedHandler)
        installedHandler()

        #expect(events == ["stop"])
        #expect(backend.terminationStatuses == [0])
    }
}

@MainActor
@Suite("LiveSignalHandlingBackend")
struct LiveSignalHandlingBackendTests {
    @Test("creates safe signal source from system primitives")
    func createsSafeSignalSource() {
        let backend = LiveSignalHandlingBackend(terminateProcess: { _ in })

        backend.ignoreSignal(SIGWINCH)
        let source = backend.makeSignalSource(signal: SIGWINCH, queue: .main)
        source.setEventHandler {}
        source.resume()

        #expect(source is LiveAppSignalSource)
    }

    @Test("termination remains injectable")
    func terminateProcess() {
        var terminationStatuses: [Int32] = []
        let backend = LiveSignalHandlingBackend {
            terminationStatuses.append($0)
        }

        backend.terminateProcess(0)

        #expect(terminationStatuses == [0])
    }
}

@Suite("LiveAppSignalSource")
struct LiveAppSignalSourceTests {
    @Test("configures real dispatch source without firing")
    func configuresDispatchSource() {
        let dispatchSource = DispatchSource.makeSignalSource(signal: SIGWINCH, queue: .main)
        let source = LiveAppSignalSource(source: dispatchSource)

        source.setEventHandler {}
        source.resume()

        #expect(dispatchSource.handle == UInt(SIGWINCH))
    }
}
