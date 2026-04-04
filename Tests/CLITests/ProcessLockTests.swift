import Foundation
import Testing

@Suite(
    "ProcessLock E2E",
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["CI"] == nil, "Requires GUI environment")
)
struct ProcessLockTests {
    private let lockPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cache/lyra/lyra.pid").path

    @Test("daemon acquires lock and writes PID file")
    func daemonWritesPID() throws {
        stopAll()

        let daemon = try launchDaemon()
        defer { terminate(daemon) }

        try waitUntil { FileManager.default.fileExists(atPath: lockPath) }
        let content = try readPID()
        #expect(content == daemon.processIdentifier)
    }

    @Test("second daemon exits immediately when lock is held")
    func secondDaemonRejected() throws {
        stopAll()

        let first = try launchDaemon()
        defer { terminate(first) }
        try waitUntil { FileManager.default.fileExists(atPath: lockPath) }

        let second = try launchDaemon()
        second.waitUntilExit()

        #expect(first.isRunning)
        #expect(!second.isRunning)
    }

    @Test("start command prints Already running when daemon holds lock")
    func startWhileLocked() throws {
        stopAll()

        let daemon = try launchDaemon()
        defer { terminate(daemon) }
        try waitUntil { FileManager.default.fileExists(atPath: lockPath) }

        let output = try runStart()
        #expect(output.contains("Already running"))
    }

    @Test("lock is released after daemon terminates, allowing a new daemon")
    func lockReleasedOnExit() throws {
        stopAll()

        let first = try launchDaemon()
        try waitUntil { FileManager.default.fileExists(atPath: lockPath) }
        let firstPID = try readPID()
        terminate(first)

        // Remove stale PID file so the new daemon writes a fresh one
        try? FileManager.default.removeItem(atPath: lockPath)

        let second = try launchDaemon()
        defer { terminate(second) }
        try waitUntil { FileManager.default.fileExists(atPath: lockPath) }

        let secondPID = try readPID()
        #expect(secondPID != firstPID)
        #expect(second.isRunning)
    }
}

// MARK: - Helpers

extension ProcessLockTests {
    private func launchDaemon() throws -> Process {
        let process = Process()
        process.executableURL = binaryURL()
        process.arguments = ["daemon"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    private func runStart() throws -> String {
        let process = Process()
        process.executableURL = binaryURL()
        process.arguments = ["start"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private func readPID() throws -> Int32 {
        let content = try String(contentsOfFile: lockPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Int32(content) ?? -1
    }

    private func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        process.waitUntilExit()
    }

    /// Kill all existing lyra daemons and remove the PID file
    private func stopAll() {
        let stop = Process()
        stop.executableURL = binaryURL()
        stop.arguments = ["stop"]
        stop.standardOutput = FileHandle.nullDevice
        stop.standardError = FileHandle.nullDevice
        try? stop.run()
        stop.waitUntilExit()
        try? FileManager.default.removeItem(atPath: lockPath)
    }

    private func waitUntil(timeout: Double = 3, condition: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                struct Timeout: Error {}
                throw Timeout()
            }
            usleep(50_000)
        }
    }

    private func binaryURL() -> URL {
        packageRoot().appendingPathComponent(".build/debug/lyra")
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
