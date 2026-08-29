import Foundation
import TestSupport
import Testing

@testable import DarwinGateway

@Suite("DarwinGateway lock", .serialized, .timeLimit(.minutes(1)))
struct DarwinGatewayLockTests {
    // MARK: - Normal Behavior

    @Suite("acquire")
    struct Acquire {
        private let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyra-lock-test-\(ProcessInfo.processInfo.processIdentifier)/acquire")

        private var lockPath: String { tempDir.appendingPathComponent("lyra.pid").path }

        @Test("writes holder's PID to file")
        func writesPID() throws {
            let lock = DarwinGateway(lockDirectory: tempDir)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            #expect(lock.acquireLock())
            let content = try String(contentsOfFile: lockPath, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(content == "\(ProcessInfo.processInfo.processIdentifier)")
        }

        @Test("is idempotent — second call returns true without side effects")
        func idempotent() {
            let lock = DarwinGateway(lockDirectory: tempDir)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            #expect(lock.acquireLock())
            #expect(lock.acquireLock())
        }
    }

    // MARK: - Cross-Process Mutual Exclusion

    @Suite("mutual exclusion", .serialized, .timeLimit(.minutes(1)))
    struct MutualExclusion {
        private let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyra-lock-test-\(ProcessInfo.processInfo.processIdentifier)/mutex")

        private var lockPath: String { tempDir.appendingPathComponent("lyra.pid").path }

        @Test("acquire fails when another process holds the lock")
        func acquireBlocked() async throws {
            defer { try? FileManager.default.removeItem(at: tempDir) }
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let holder = try FlockHelper.launchHolder(lockPath: lockPath)
            defer { holder.terminate() }
            try #require(await pollUntil(timeout: .seconds(30)) { lockFileHasContent(at: lockPath) })

            let lock = DarwinGateway(lockDirectory: tempDir)
            #expect(!lock.acquireLock())
        }

        @Test("isLocked returns true when another process holds the lock")
        func isLockedTrue() async throws {
            defer { try? FileManager.default.removeItem(at: tempDir) }
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let holder = try FlockHelper.launchHolder(lockPath: lockPath)
            defer { holder.terminate() }
            try #require(await pollUntil(timeout: .seconds(30)) { lockFileHasContent(at: lockPath) })

            let lock = DarwinGateway(lockDirectory: tempDir)
            #expect(lock.isLocked)
        }

        @Test("isLocked returns false when no lock file exists")
        func isLockedNoFile() {
            let lock = DarwinGateway(lockDirectory: tempDir)
            #expect(!lock.isLocked)
        }

        @Test("isLocked returns true when current instance holds the lock")
        func isLockedForCurrentHolder() {
            let lock = DarwinGateway(lockDirectory: tempDir)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            #expect(lock.acquireLock())
            #expect(lock.isLocked)
        }
    }

    // MARK: - Lock Release on Process Death

    @Suite("process death releases lock", .serialized, .timeLimit(.minutes(1)))
    struct ProcessDeath {
        private let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyra-lock-test-\(ProcessInfo.processInfo.processIdentifier)/death")

        private var lockPath: String { tempDir.appendingPathComponent("lyra.pid").path }

        @Test("isLocked returns false immediately after holder is SIGKILL'd")
        func isLockedAfterKill() async throws {
            defer { try? FileManager.default.removeItem(at: tempDir) }
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let holder = try FlockHelper.launchHolder(lockPath: lockPath)
            try #require(await pollUntil(timeout: .seconds(30)) { lockFileHasContent(at: lockPath) })

            kill(holder.processIdentifier, SIGKILL)
            await holder.waitForExit()

            let lock = DarwinGateway(lockDirectory: tempDir)
            #expect(!lock.isLocked)
        }

        @Test("acquire succeeds immediately after holder is SIGKILL'd")
        func acquireAfterKill() async throws {
            defer { try? FileManager.default.removeItem(at: tempDir) }
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let holder = try FlockHelper.launchHolder(lockPath: lockPath)
            try #require(await pollUntil(timeout: .seconds(30)) { lockFileHasContent(at: lockPath) })

            kill(holder.processIdentifier, SIGKILL)
            await holder.waitForExit()

            let lock = DarwinGateway(lockDirectory: tempDir)
            #expect(lock.acquireLock())
        }
    }

    // MARK: - Child Process Isolation (O_CLOEXEC)

    @Suite("child process isolation", .serialized, .timeLimit(.minutes(1)))
    struct ChildProcessIsolation {
        private let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyra-lock-test-\(ProcessInfo.processInfo.processIdentifier)/child")

        private var lockPath: String { tempDir.appendingPathComponent("lyra.pid").path }
        private var childReadyPath: String { tempDir.appendingPathComponent("child-ready").path }

        @Test("killing holder releases lock even when its child process is still alive")
        func childDoesNotInheritLock() async throws {
            defer { try? FileManager.default.removeItem(at: tempDir) }
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let holder = try FlockHelper.launchHolderWithChild(lockPath: lockPath, childReadyPath: childReadyPath)
            let pid = holder.processIdentifier
            try #require(await pollUntil(timeout: .seconds(30)) { lockFileHasContent(at: lockPath) })
            try #require(await pollUntil(timeout: .seconds(30)) { FileManager.default.fileExists(atPath: childReadyPath) })

            // Kill only the parent after the child has crossed an exec boundary.
            kill(pid, SIGKILL)
            await holder.waitForExit()

            let lock = DarwinGateway(lockDirectory: tempDir)
            #expect(lock.acquireLock(), "child must not inherit flock fd")

            // Clean up orphaned child process
            kill(-pid, SIGKILL)
        }
    }

    // MARK: - Cleanup

    @Suite("cleanup", .serialized, .timeLimit(.minutes(1)))
    struct Cleanup {
        private let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyra-lock-test-\(ProcessInfo.processInfo.processIdentifier)/cleanup")

        private var lockPath: String { tempDir.appendingPathComponent("lyra.pid").path }

        @Test("truncates PID file content but preserves the file")
        func truncatesFile() throws {
            let lock = DarwinGateway(lockDirectory: tempDir)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            #expect(lock.acquireLock())
            lock.releaseLock()

            #expect(FileManager.default.fileExists(atPath: lockPath))
            let content = try String(contentsOfFile: lockPath, encoding: .utf8)
            #expect(content.isEmpty)
        }

        @Test("releaseLock lets same instance reacquire")
        func releaseThenReacquire() {
            let lock = DarwinGateway(lockDirectory: tempDir)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            #expect(lock.acquireLock())
            lock.releaseLock()
            #expect(lock.acquireLock())
        }

        @Test("does not crash when lock file does not exist")
        func cleanupMissingFile() {
            let lock = DarwinGateway(lockDirectory: tempDir)
            lock.releaseLock()
        }

        @Test("another process can acquire on same inode after holder exits and cleanup")
        func reacquireAfterCleanup() async throws {
            defer { try? FileManager.default.removeItem(at: tempDir) }
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let holder = try FlockHelper.launchHolder(lockPath: lockPath)
            try #require(await pollUntil(timeout: .seconds(30)) { lockFileHasContent(at: lockPath) })
            holder.terminate()
            await holder.waitForExit()

            let cleaner = DarwinGateway(lockDirectory: tempDir)
            cleaner.releaseLock()

            let lock = DarwinGateway(lockDirectory: tempDir)
            #expect(lock.acquireLock())
        }
    }
}

// MARK: - Test Helpers

/// Whether the lock file at `path` has been written with non-blank content —
/// the predicate `pollUntil` polls for readiness of a holder process's flock write.
private func lockFileHasContent(at path: String) -> Bool {
    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return false }
    return !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

enum FlockHelper {
    static func launchHolder(lockPath: String) throws -> LaunchedProcess {
        let script = """
            use Fcntl qw(:flock);
            open(my $fh, ">", $ARGV[0]) or die;
            flock($fh, LOCK_EX) or die;
            syswrite($fh, "$$\\n");
            sleep(600);
            """
        return try LaunchedProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/perl"), arguments: ["-e", script, lockPath])
    }

    static func launchHolderWithChild(lockPath: String, childReadyPath: String) throws -> LaunchedProcess {
        let script = """
            use Fcntl qw(:flock);
            use POSIX qw(setpgid);
            setpgid(0, 0);
            open(my $fh, ">", $ARGV[0]) or die;
            flock($fh, LOCK_EX) or die;
            syswrite($fh, "$$\\n");
            my $pid = fork();
            if ($pid == 0) {
                exec("/bin/sh", "-c", 'echo ready > "$1"; exec sleep 600', "sh", $ARGV[1]);
            }
            sleep(600);
            """
        return try LaunchedProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/perl"), arguments: ["-e", script, lockPath, childReadyPath])
    }
}
