import Dependencies

public protocol ProcessHandler: Sendable {
    func start() throws -> StartResult
    func stop() -> StopResult
    func restart() throws -> StartResult
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
    func start() throws -> StartResult { fatalError("ProcessHandler.start not implemented") }
    func stop() -> StopResult { fatalError("ProcessHandler.stop not implemented") }
    func restart() throws -> StartResult { fatalError("ProcessHandler.restart not implemented") }
    func acquireDaemonLock() -> Bool { fatalError("ProcessHandler.acquireDaemonLock not implemented") }
}
