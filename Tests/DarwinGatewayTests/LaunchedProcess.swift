import Foundation
import TestSupport

/// A child process a test launches, with its exit recorded where an `async` test can
/// await it.
///
/// `Process.waitUntilExit()` is not used after an `await`: it runs the *calling*
/// thread's run loop, while Foundation delivers the exit to the run loop of the
/// thread that launched the process. Once a test suspends, it may resume on another
/// cooperative thread, and the join then never returns — the full-suite hang caught
/// in #349 steps 3–4, `reacquireAfterCleanup` parked in `waitUntilExit` with the
/// child already reaped. The termination handler is a callback the test owns, so it
/// is recorded into a `Collector` and awaited like any other spy.
struct LaunchedProcess {
    let process: Process
    private let exited: Collector<Void>

    init(executableURL: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let exited = Collector<Void>()
        process.terminationHandler = { _ in exited.append(()) }
        try process.run()
        self.process = process
        self.exited = exited
    }

    var processIdentifier: Int32 { process.processIdentifier }

    /// Sends SIGTERM if the child is still running — the signal only. Pair it with
    /// `waitForExit()` when the test depends on the exit having happened.
    func terminate() {
        guard process.isRunning else { return }
        process.terminate()
    }

    func waitForExit() async {
        await exited.waitForCount(1)
    }
}
