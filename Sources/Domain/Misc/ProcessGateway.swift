import Dependencies

public protocol ProcessGateway: Sendable {
    // Resource sampling
    var resourceSnapshot: ResourceSnapshot { get }

    // Process discovery
    var overlayPIDs: [Int32] { get }

    // Process spawning
    func spawnDaemon(executablePath: String) -> Int32?

    // Signals
    func sendSignal(_ pid: Int32, signal: Int32) -> Bool
    func isRunning(_ pid: Int32) -> Bool

    // Lock (PID file + flock)
    func acquireLock() -> Bool
    var isLocked: Bool { get }
    func releaseLock()

    // launchctl
    @discardableResult
    func runLaunchctl(_ arguments: [String]) -> Int32

    // Executable discovery
    func findExecutable(_ name: String) -> String?

    // Subprocess execution
    func run(executable: String, arguments: [String]) -> Int32
    func runInteractive(executable: String, arguments: [String]) -> Int32
    func runCapturingOutput(executable: String, arguments: [String]) -> String?
    func runStreaming(executable: String, arguments: [String]) -> AsyncStream<String>
}

public enum ProcessGatewayKey: TestDependencyKey {
    public static let testValue: any ProcessGateway = UnimplementedProcessGateway()
}

extension DependencyValues {
    public var processGateway: any ProcessGateway {
        get { self[ProcessGatewayKey.self] }
        set { self[ProcessGatewayKey.self] = newValue }
    }
}

private struct UnimplementedProcessGateway: ProcessGateway {
    var resourceSnapshot: ResourceSnapshot { fatalError("ProcessGateway.resourceSnapshot not implemented") }
    var overlayPIDs: [Int32] { fatalError("ProcessGateway.overlayPIDs not implemented") }
    func spawnDaemon(executablePath: String) -> Int32? { fatalError("ProcessGateway.spawnDaemon not implemented") }
    func sendSignal(_ pid: Int32, signal: Int32) -> Bool { fatalError("ProcessGateway.sendSignal not implemented") }
    func isRunning(_ pid: Int32) -> Bool { fatalError("ProcessGateway.isRunning not implemented") }
    func acquireLock() -> Bool { fatalError("ProcessGateway.acquireLock not implemented") }
    var isLocked: Bool { fatalError("ProcessGateway.isLocked not implemented") }
    func releaseLock() { fatalError("ProcessGateway.releaseLock not implemented") }
    func runLaunchctl(_ arguments: [String]) -> Int32 { fatalError("ProcessGateway.runLaunchctl not implemented") }
    func findExecutable(_ name: String) -> String? { fatalError("ProcessGateway.findExecutable not implemented") }
    func run(executable: String, arguments: [String]) -> Int32 { fatalError("ProcessGateway.run not implemented") }
    func runInteractive(executable: String, arguments: [String]) -> Int32 {
        fatalError("ProcessGateway.runInteractive not implemented")
    }
    func runCapturingOutput(executable: String, arguments: [String]) -> String? {
        fatalError("ProcessGateway.runCapturingOutput not implemented")
    }
    func runStreaming(executable: String, arguments: [String]) -> AsyncStream<String> {
        fatalError("ProcessGateway.runStreaming not implemented")
    }
}
