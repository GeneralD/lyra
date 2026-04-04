import Foundation

/// Manages an exclusive `flock` on a PID file.
/// The lock lives as long as this instance (or the process) is alive.
public final class ProcessLock: @unchecked Sendable {
    public static let shared = ProcessLock(
        directory: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/lyra")
    )

    private let lockURL: URL
    private var fileDescriptor: Int32?

    public init(directory: URL) {
        self.lockURL = directory.appendingPathComponent("lyra.pid")
    }

    /// Try to acquire an exclusive lock and write our PID.
    /// Returns `true` on success; subsequent calls return `true` if already acquired.
    public func acquire() -> Bool {
        guard fileDescriptor == nil else { return true }

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

        fileDescriptor = fd
        return true
    }

    /// Check whether another process currently holds the lock.
    public var isLocked: Bool {
        let fd = open(lockURL.path, O_RDONLY)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { return true }
        flock(fd, LOCK_UN)
        return false
    }

    /// Clear the PID file without removing it, preserving the inode for flock.
    public func cleanup() {
        let fd = open(lockURL.path, O_WRONLY)
        guard fd >= 0 else { return }
        defer { close(fd) }
        ftruncate(fd, 0)
    }
}
