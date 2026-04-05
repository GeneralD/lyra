import Dependencies

public protocol ProcessManaging: Sendable {
    func findOverlayPIDs() -> [Int32]
}

public enum ProcessManagingKey: TestDependencyKey {
    public static let testValue: any ProcessManaging = UnimplementedProcessManaging()
}

extension DependencyValues {
    public var processManaging: any ProcessManaging {
        get { self[ProcessManagingKey.self] }
        set { self[ProcessManagingKey.self] = newValue }
    }
}

private struct UnimplementedProcessManaging: ProcessManaging {
    func findOverlayPIDs() -> [Int32] { fatalError("ProcessManaging.findOverlayPIDs not implemented") }
}
