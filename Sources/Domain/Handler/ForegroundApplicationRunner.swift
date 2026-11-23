import Dependencies

public struct ForegroundApplicationRunner: Sendable {
    public let runAccessory: @MainActor @Sendable () -> Void

    public init(runAccessory: @escaping @MainActor @Sendable () -> Void) {
        self.runAccessory = runAccessory
    }
}

public enum ForegroundApplicationRunnerKey: TestDependencyKey {
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
