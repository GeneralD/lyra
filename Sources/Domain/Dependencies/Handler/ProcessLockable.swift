import Dependencies

public protocol ProcessLockable: Sendable {
    func acquire() -> Bool
    var isLocked: Bool { get }
    func cleanup()
}

public enum ProcessLockKey: TestDependencyKey {
    public static let testValue: any ProcessLockable = UnimplementedProcessLock()
}

extension DependencyValues {
    public var processLock: any ProcessLockable {
        get { self[ProcessLockKey.self] }
        set { self[ProcessLockKey.self] = newValue }
    }
}

private struct UnimplementedProcessLock: ProcessLockable {
    func acquire() -> Bool { fatalError("ProcessLock.acquire not implemented") }
    var isLocked: Bool { fatalError("ProcessLock.isLocked not implemented") }
    func cleanup() { fatalError("ProcessLock.cleanup not implemented") }
}
