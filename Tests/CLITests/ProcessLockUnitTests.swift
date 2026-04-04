import Foundation
import Testing

@testable import CLI

@Suite("ProcessLock unit", .serialized)
struct ProcessLockUnitTests {
    private let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("lyra-lock-test-\(ProcessInfo.processInfo.processIdentifier)")
    private let lockFileName = "lyra.pid"

    private var lockPath: String { tempDir.appendingPathComponent(lockFileName).path }

    // MARK: - acquire

    @Test("acquire succeeds and writes PID file")
    func acquireWritesPID() throws {
        let lock = ProcessLock(directory: tempDir)
        defer { cleanupDir() }

        #expect(lock.acquire())
        let content = try String(contentsOfFile: lockPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(content == "\(ProcessInfo.processInfo.processIdentifier)")
    }

    @Test("acquire is idempotent — second call returns true")
    func acquireIdempotent() {
        let lock = ProcessLock(directory: tempDir)
        defer { cleanupDir() }

        #expect(lock.acquire())
        #expect(lock.acquire())
    }

    @Test("acquire fails when another process holds flock")
    func acquireFailsWhenHeld() throws {
        defer { cleanupDir() }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let holder = try launchFlockHolder()
        defer { terminate(holder) }
        try waitUntil { FileManager.default.fileExists(atPath: lockPath) }

        let lock = ProcessLock(directory: tempDir)
        #expect(!lock.acquire())
    }

    // MARK: - isLocked

    @Test("isLocked returns false when no lock file exists")
    func isLockedNoFile() {
        let lock = ProcessLock(directory: tempDir)
        #expect(!lock.isLocked)
    }

    @Test("isLocked returns true when another process holds flock")
    func isLockedWhenHeld() throws {
        defer { cleanupDir() }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let holder = try launchFlockHolder()
        defer { terminate(holder) }
        try waitUntil { FileManager.default.fileExists(atPath: lockPath) }

        let lock = ProcessLock(directory: tempDir)
        #expect(lock.isLocked)
    }

    @Test("isLocked returns false after holder exits")
    func isLockedReleasedOnExit() throws {
        defer { cleanupDir() }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let holder = try launchFlockHolder()
        try waitUntil { FileManager.default.fileExists(atPath: lockPath) }
        terminate(holder)

        let lock = ProcessLock(directory: tempDir)
        #expect(!lock.isLocked)
    }

    // MARK: - cleanup

    @Test("cleanup truncates PID file but preserves the file")
    func cleanupTruncates() throws {
        let lock = ProcessLock(directory: tempDir)
        defer { cleanupDir() }

        #expect(lock.acquire())
        lock.cleanup()

        #expect(FileManager.default.fileExists(atPath: lockPath))
        let content = try String(contentsOfFile: lockPath, encoding: .utf8)
        #expect(content.isEmpty)
    }
}

// MARK: - Helpers

extension ProcessLockUnitTests {
    /// Launch a subprocess that holds an exclusive flock on the test PID file.
    private func launchFlockHolder() throws -> Process {
        let script = """
            use Fcntl qw(:flock);
            open(my $fh, ">", $ARGV[0]) or die;
            flock($fh, LOCK_EX) or die;
            print $fh "$$\\n";
            $| = 1;
            sleep(600);
            """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = ["-e", script, lockPath]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    private func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        process.waitUntilExit()
    }

    private func cleanupDir() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func waitUntil(timeout: Double = 30, condition: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                struct Timeout: Error {}
                throw Timeout()
            }
            usleep(100_000)
        }
    }
}
