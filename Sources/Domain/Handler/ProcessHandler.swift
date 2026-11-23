import Dependencies

public protocol ProcessHandler: Sendable {
    func start() async -> StartResult
    func stop() async -> StopResult
    func restart() async -> StartResult
    func acquireDaemonLock() -> Bool
}

public enum ProcessHandlerKey: TestDependencyKey {
    public static let testValue: any ProcessHandler = UnimplementedProcessHandler()
}

extension DependencyValues {
    public var processHandler: any ProcessHandler {
        get { self[ProcessHandlerKey.self] }
        set { self[ProcessHandlerKey.self] = newValue }
    }
}

private struct UnimplementedProcessHandler: ProcessHandler {
    func start() async -> StartResult { fatalError("ProcessHandler.start not implemented") }
    func stop() async -> StopResult { fatalError("ProcessHandler.stop not implemented") }
    func restart() async -> StartResult { fatalError("ProcessHandler.restart not implemented") }
    func acquireDaemonLock() -> Bool { fatalError("ProcessHandler.acquireDaemonLock not implemented") }
}
