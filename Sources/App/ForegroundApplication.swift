import AppKit
import Dependencies

@MainActor
public enum ForegroundApplication {
    public static func runAccessory() {
        runAccessory(
            backend: NSApplicationForegroundBackend(),
            delegateFactory: { AppDelegate() }
        )
    }

    static func runAccessory(
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
protocol ForegroundApplicationBackend: AnyObject {
    func setAccessoryActivationPolicy()
    func setDelegate(_ delegate: any NSApplicationDelegate)
    func run()
}

@MainActor
protocol ForegroundApplicationProcess: AnyObject {
    @discardableResult
    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool
    var delegate: (any NSApplicationDelegate)? { get set }
    func run()
}

extension NSApplication: ForegroundApplicationProcess {}

@MainActor
final class NSApplicationForegroundBackend: ForegroundApplicationBackend {
    private let application: any ForegroundApplicationProcess

    init(application: any ForegroundApplicationProcess = NSApplication.shared) {
        self.application = application
    }

    func setAccessoryActivationPolicy() {
        application.setActivationPolicy(.accessory)
    }

    func setDelegate(_ delegate: any NSApplicationDelegate) {
        application.delegate = delegate
    }

    func run() {
        application.run()
    }
}

public struct ForegroundApplicationRunner: Sendable {
    public let runAccessory: @MainActor @Sendable () -> Void

    public init(runAccessory: @escaping @MainActor @Sendable () -> Void) {
        self.runAccessory = runAccessory
    }
}

public enum ForegroundApplicationRunnerKey: DependencyKey {
    public static let liveValue = ForegroundApplicationRunner(
        runAccessory: { ForegroundApplication.runAccessory() }
    )
    public static let testValue = ForegroundApplicationRunner {
        fatalError("ForegroundApplicationRunner.runAccessory not implemented")
    }
}

extension DependencyValues {
    public var foregroundApplicationRunner: ForegroundApplicationRunner {
        get { self[ForegroundApplicationRunnerKey.self] }
        set { self[ForegroundApplicationRunnerKey.self] = newValue }
    }
}
