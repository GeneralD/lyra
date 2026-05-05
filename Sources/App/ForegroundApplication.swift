import AppKit
import Dependencies

@MainActor
public enum ForegroundApplication {
    public static func runAccessory() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
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
        runAccessory: ForegroundApplication.runAccessory
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
