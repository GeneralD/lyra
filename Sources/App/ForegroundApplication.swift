import AppKit

@MainActor
public enum ForegroundApplication {
    public static func runAccessory(
        backend: any ForegroundApplicationBackend,
        delegateFactory: @escaping @MainActor () -> any NSApplicationDelegate
    ) {
        backend.setAccessoryActivationPolicy()
        let delegate = delegateFactory()
        backend.setDelegate(delegate)
        withExtendedLifetime(delegate) {
            backend.run()
        }
    }
}

@MainActor
public protocol ForegroundApplicationBackend: AnyObject {
    func setAccessoryActivationPolicy()
    func setDelegate(_ delegate: any NSApplicationDelegate)
    func run()
}

@MainActor
public protocol ForegroundApplicationProcess: AnyObject {
    @discardableResult
    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool
    var delegate: (any NSApplicationDelegate)? { get set }
    func run()
}

extension NSApplication: ForegroundApplicationProcess {}

@MainActor
public final class NSApplicationForegroundBackend: ForegroundApplicationBackend {
    private let application: any ForegroundApplicationProcess

    public init(application: any ForegroundApplicationProcess) {
        self.application = application
    }

    public func setAccessoryActivationPolicy() {
        application.setActivationPolicy(.accessory)
    }

    public func setDelegate(_ delegate: any NSApplicationDelegate) {
        application.delegate = delegate
    }

    public func run() {
        application.run()
    }
}
