import Foundation
import os

/// Manages an exclusive `flock` on a PID file.
/// The lock lives as long as this instance (or the process) is alive.
/// On deinit, the file descriptor is closed and the flock is released.
public final class ProcessLock: Sendable {
    public static let shared = ProcessLock(
        directory: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/lyra")
    )

    private let lockURL: URL
    private let state = OSAllocatedUnfairLock(initialState: State())

    public init(directory: URL) {
        self.lockURL = directory.appendingPathComponent("lyra.pid")
    }

    deinit {
        _ = state.withLock { state in
            state.fileDescriptor.map { close($0) }
        }
    }

    /// Try to acquire an exclusive lock and write our PID.
    /// Returns `true` on success; subsequent calls return `true` if already acquired.
    public func acquire() -> Bool {
        state.withLock { state in
            guard state.fileDescriptor == nil else { return true }

            let dir = lockURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let fd = open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
            guard fd >= 0, flock(fd, LOCK_EX | LOCK_NB) == 0 else {
                if fd >= 0 { close(fd) }
                return false
            }

            ftruncate(fd, 0)
            let pidString = "\(ProcessInfo.processInfo.processIdentifier)\n"
            _ = pidString.withCString { Darwin.write(fd, $0, strlen($0)) }

            state.fileDescriptor = fd
            return true
        }
    }

    /// Check whether another process currently holds the lock.
    /// Short-circuits to `false` when this instance already owns the lock.
    /// Returns `true` on permission errors (fail-safe).
    public var isLocked: Bool {
        if state.withLock({ $0.fileDescriptor != nil }) { return false }

        let fd = open(lockURL.path, O_RDONLY)
        guard fd >= 0 else { return errno != ENOENT }
        defer { close(fd) }

        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { return true }
        flock(fd, LOCK_UN)
        return false
    }

    /// Clear the PID file content, preserving the inode for flock.
    /// Only truncates if this instance holds the lock or no other process does.
    public func cleanup() {
        if let fd = state.withLock({ $0.fileDescriptor }) {
            ftruncate(fd, 0)
            return
        }

        let fd = open(lockURL.path, O_WRONLY)
        guard fd >= 0 else { return }
        defer { close(fd) }

        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { return }
        defer { flock(fd, LOCK_UN) }
        ftruncate(fd, 0)
    }
}

private struct State {
    var fileDescriptor: Int32?
}
