import Domain

struct FakeLaunchError: Error {}

/// Fake `ProcessGateway` for exercising `ProcessExecutorImpl` in isolation. Only
/// `runProcess` carries behavior; the rest of the wide gateway surface is unused
/// here and fatal-errors if ever touched.
final class FakeProcessGateway: ProcessGateway, @unchecked Sendable {
    enum Behavior {
        /// Never completes until the surrounding task is cancelled, then propagates
        /// `CancellationError` — mirrors the live gateway killing a hung child when
        /// the executor's timeout fires.
        case hang
        /// Completes immediately with a fixed result.
        case returns((status: Int32, stdout: String, stderr: String))
        /// Throws immediately, as the live gateway does when the executable can't launch.
        case throwsLaunchError
    }

    let behavior: Behavior
    private let recorded = RecordedCall()
    init(_ behavior: Behavior) { self.behavior = behavior }

    /// The arguments the most recent `runProcess` was called with (for pass-through assertions).
    var lastCall: (executable: String, arguments: [String], environment: [String: String])? {
        recorded.value
    }

    func runProcess(
        executable: String, arguments: [String], environment: [String: String]
    ) async throws -> (status: Int32, stdout: String, stderr: String) {
        recorded.value = (executable, arguments, environment)
        switch behavior {
        case .returns(let result):
            return result
        case .throwsLaunchError:
            throw FakeLaunchError()
        case .hang:
            try await withTaskCancellationHandler {
                while true {
                    try Task.checkCancellation()
                    await Task.yield()
                }
            } onCancel: {
            }
            // Unreachable — the loop only exits by throwing on cancellation.
            return (status: 0, stdout: "", stderr: "")
        }
    }

    // MARK: Unused gateway surface

    var resourceSnapshot: ResourceSnapshot { .init(cpuUser: 0, cpuSystem: 0, peakRSS: 0, currentRSS: 0) }
    var overlayPIDs: [Int32] { [] }
    func spawnDaemon(executablePath: String) -> Int32? { fatalError("unused") }
    func sendSignal(_ pid: Int32, signal: Int32) -> Bool { fatalError("unused") }
    func isRunning(_ pid: Int32) -> Bool { fatalError("unused") }
    func acquireLock() -> Bool { fatalError("unused") }
    var isLocked: Bool { fatalError("unused") }
    func releaseLock() { fatalError("unused") }
    func runLaunchctl(_ arguments: [String]) -> Int32 { fatalError("unused") }
    func findExecutable(_ name: String) -> String? { fatalError("unused") }
    func run(executable: String, arguments: [String]) -> Int32 { fatalError("unused") }
    func runInteractiveShell(_ command: String) -> Int32 { fatalError("unused") }
    func runCapturingOutput(executable: String, arguments: [String]) -> String? { fatalError("unused") }
    func runStreaming(executable: String, arguments: [String]) -> AsyncStream<String> { fatalError("unused") }
}

/// Lock-free single-writer/single-reader box (`@unchecked` on the enclosing class).
private final class RecordedCall: @unchecked Sendable {
    var value: (executable: String, arguments: [String], environment: [String: String])?
}
