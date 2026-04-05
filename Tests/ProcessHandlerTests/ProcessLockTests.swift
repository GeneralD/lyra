import Foundation
import Testing

@testable import ProcessHandler

@Suite("ProcessLock", .serialized)
struct ProcessLockSpec {
    // MARK: - Normal Behavior

    @Suite("acquire")
    struct Acquire {
        private let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyra-lock-test-\(ProcessInfo.processInfo.processIdentifier)/acquire")

        private var lockPath: String { tempDir.appendingPathComponent("lyra.pid").path }

        @Test("writes holder's PID to file")
        func writesPID() throws {
            let lock = ProcessLock(directory: tempDir)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            #expect(lock.acquire())
            let content = try String(contentsOfFile: lockPath, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(content == "\(ProcessInfo.processInfo.processIdentifier)")
        }

        @Test("is idempotent — second call returns true without side effects")
        func idempotent() {
            let lock = ProcessLock(directory: tempDir)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            #expect(lock.acquire())
            #expect(lock.acquire())
        }
    }

    // MARK: - Cross-Process Mutual Exclusion

    @Suite("mutual exclusion", .serialized)
    struct MutualExclusion {
        private let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyra-lock-test-\(ProcessInfo.processInfo.processIdentifier)/mutex")

        private var lockPath: String { tempDir.appendingPathComponent("lyra.pid").path }

        @Test("acquire fails when another process holds the lock")
        func acquireBlocked() throws {
            defer { try? FileManager.default.removeItem(at: tempDir) }
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let holder = try FlockHelper.launchHolder(lockPath: lockPath)
            defer { FlockHelper.terminate(holder) }
            try FlockHelper.waitForLockFile(atPath: lockPath)

            let lock = ProcessLock(directory: tempDir)
            #expect(!lock.acquire())
        }

        @Test("isLocked returns true when another process holds the lock")
        func isLockedTrue() throws {
            defer { try? FileManager.default.removeItem(at: tempDir) }
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let holder = try FlockHelper.launchHolder(lockPath: lockPath)
            defer { FlockHelper.terminate(holder) }
            try FlockHelper.waitForLockFile(atPath: lockPath)

            let lock = ProcessLock(directory: tempDir)
            #expect(lock.isLocked)
        }

        @Test("isLocked returns false when no lock file exists")
        func isLockedNoFile() {
            let lock = ProcessLock(directory: tempDir)
            #expect(!lock.isLocked)
        }
    }

    // MARK: - Lock Release on Process Death

    @Suite("process death releases lock", .serialized)
    struct ProcessDeath {
        private let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyra-lock-test-\(ProcessInfo.processInfo.processIdentifier)/death")

        private var lockPath: String { tempDir.appendingPathComponent("lyra.pid").path }

        @Test("isLocked returns false immediately after holder is SIGKILL'd")
        func isLockedAfterKill() throws {
            defer { try? FileManager.default.removeItem(at: tempDir) }
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let holder = try FlockHelper.launchHolder(lockPath: lockPath)
            try FlockHelper.waitForLockFile(atPath: lockPath)

            kill(holder.processIdentifier, SIGKILL)
            holder.waitUntilExit()

            let lock = ProcessLock(directory: tempDir)
            #expect(!lock.isLocked)
        }

        @Test("acquire succeeds immediately after holder is SIGKILL'd")
        func acquireAfterKill() throws {
            defer { try? FileManager.default.removeItem(at: tempDir) }
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let holder = try FlockHelper.launchHolder(lockPath: lockPath)
            try FlockHelper.waitForLockFile(atPath: lockPath)

            kill(holder.processIdentifier, SIGKILL)
            holder.waitUntilExit()

            let lock = ProcessLock(directory: tempDir)
            #expect(lock.acquire())
        }
    }

    // MARK: - Child Process Isolation (O_CLOEXEC)

    @Suite("child process isolation", .serialized)
    struct ChildProcessIsolation {
        private let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyra-lock-test-\(ProcessInfo.processInfo.processIdentifier)/child")

        private var lockPath: String { tempDir.appendingPathComponent("lyra.pid").path }

        @Test("killing holder releases lock even when its child process is still alive")
        func childDoesNotInheritLock() throws {
            defer { try? FileManager.default.removeItem(at: tempDir) }
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let holder = try FlockHelper.launchHolderWithChild(lockPath: lockPath)
            let pid = holder.processIdentifier
            try FlockHelper.waitForLockFile(atPath: lockPath)

            // Kill only the parent — child stays alive
            kill(pid, SIGKILL)
            holder.waitUntilExit()

            let lock = ProcessLock(directory: tempDir)
            #expect(lock.acquire(), "child must not inherit flock fd")

            // Clean up orphaned child process
            kill(-pid, SIGKILL)
        }
    }

    // MARK: - Cleanup

    @Suite("cleanup", .serialized)
    struct Cleanup {
        private let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyra-lock-test-\(ProcessInfo.processInfo.processIdentifier)/cleanup")

        private var lockPath: String { tempDir.appendingPathComponent("lyra.pid").path }

        @Test("truncates PID file content but preserves the file")
        func truncatesFile() throws {
            let lock = ProcessLock(directory: tempDir)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            #expect(lock.acquire())
            lock.cleanup()

            #expect(FileManager.default.fileExists(atPath: lockPath))
            let content = try String(contentsOfFile: lockPath, encoding: .utf8)
            #expect(content.isEmpty)
        }

        @Test("does not crash when lock file does not exist")
        func cleanupMissingFile() {
            let lock = ProcessLock(directory: tempDir)
            lock.cleanup()
        }

        @Test("another process can acquire on same inode after holder exits and cleanup")
        func reacquireAfterCleanup() throws {
            defer { try? FileManager.default.removeItem(at: tempDir) }
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let holder = try FlockHelper.launchHolder(lockPath: lockPath)
            try FlockHelper.waitForLockFile(atPath: lockPath)
            FlockHelper.terminate(holder)

            let cleaner = ProcessLock(directory: tempDir)
            cleaner.cleanup()

            let lock = ProcessLock(directory: tempDir)
            #expect(lock.acquire())
        }
    }
}

// MARK: - Test Helpers

enum FlockHelper {
    static func launchHolder(lockPath: String) throws -> Process {
        let script = """
            use Fcntl qw(:flock);
            open(my $fh, ">", $ARGV[0]) or die;
            flock($fh, LOCK_EX) or die;
            syswrite($fh, "$$\\n");
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

    static func launchHolderWithChild(lockPath: String) throws -> Process {
        let script = """
            use Fcntl qw(:flock);
            use POSIX qw(setpgid);
            setpgid(0, 0);
            open(my $fh, ">", $ARGV[0]) or die;
            flock($fh, LOCK_EX) or die;
            syswrite($fh, "$$\\n");
            my $pid = fork();
            if ($pid == 0) {
                exec("sleep", "600");
            }
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

    static func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        process.waitUntilExit()
    }

    static func waitForLockFile(atPath path: String, timeout: Double = 30) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let content = try? String(contentsOfFile: path, encoding: .utf8),
                !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return
            }
            guard Date() < deadline else {
                struct Timeout: Error {}
                throw Timeout()
            }
            usleep(50_000)
        }
    }
}
