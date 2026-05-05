import AppKit
import AppRouter

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let routerFactory: @MainActor () -> any AppRouting
    private let terminationHandler: any TerminationHandling
    private var router: (any AppRouting)?

    public override convenience init() {
        self.init(
            routerFactory: { AppRouter() },
            terminationHandler: SignalTerminationHandler()
        )
    }

    init(
        routerFactory: @escaping @MainActor () -> any AppRouting,
        terminationHandler: any TerminationHandling
    ) {
        self.routerFactory = routerFactory
        self.terminationHandler = terminationHandler
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let router = routerFactory()
        self.router = router
        router.start()

        terminationHandler.install {
            router.stop()
        }
    }
}

@MainActor
protocol AppRouting: AnyObject {
    func start()
    func stop()
}

extension AppRouter: AppRouting {}

@MainActor
protocol TerminationHandling: AnyObject {
    func install(onTermination: @escaping @MainActor () -> Void)
}
