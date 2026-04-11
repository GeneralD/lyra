import Darwin
import Domain
import Foundation
import os

public final class DarwinGateway: @unchecked Sendable {
    private let lockState = OSAllocatedUnfairLock(initialState: LockState())
    private let lockDirectory: URL

    public init(
        lockDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/lyra")
    ) {
        self.lockDirectory = lockDirectory
    }

    deinit {
        _ = lockState.withLock { state in
            state.fileDescriptor.map { close($0) }
        }
    }
}

private struct LockState {
    var fileDescriptor: Int32?
}

// MARK: - ProcessGateway

extension DarwinGateway: ProcessGateway {

    // MARK: Resource Sampling

    public var resourceSnapshot: ResourceSnapshot {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else {
            return ResourceSnapshot(cpuUser: 0, cpuSystem: 0, peakRSS: 0, currentRSS: 0)
        }

        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), intPtr, &count)
            }
        }

        return ResourceSnapshot(
            cpuUser: usage.ru_utime.fractionalSeconds,
            cpuSystem: usage.ru_stime.fractionalSeconds,
            peakRSS: Int64(usage.ru_maxrss),
            currentRSS: kr == KERN_SUCCESS ? Int64(info.resident_size) : 0
        )
    }

    // MARK: Process Discovery

    public var overlayPIDs: [Int32] {
        let myPID = ProcessInfo.processInfo.processIdentifier
        guard let output = runCapturingOutput(executable: "/usr/bin/pgrep", arguments: ["-f", "lyra"]) else {
            return []
        }
        return
            output
            .split(separator: "\n")
            .compactMap { Int32($0) }
            .filter { $0 != myPID }
    }

    // MARK: Process Spawning

    public func spawnDaemon(executablePath: String) -> Int32? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executablePath)
        task.arguments = ["daemon"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return nil }
        return task.processIdentifier
    }

    // MARK: Signals

    public func sendSignal(_ pid: Int32, signal: Int32) -> Bool {
        kill(pid, signal) == 0
    }

    public func isRunning(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0
    }

    // MARK: Lock

    public func acquireLock() -> Bool {
        lockState.withLock { state in
            guard state.fileDescriptor == nil else { return true }

            let lockURL = lockURL
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

    public var isLocked: Bool {
        if lockState.withLock({ $0.fileDescriptor != nil }) { return true }

        let fd = open(lockURL.path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { return errno != ENOENT }
        defer { close(fd) }

        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { return true }
        flock(fd, LOCK_UN)
        return false
    }

    public func releaseLock() {
        if let fd = lockState.withLock({ state -> Int32? in
            let fd = state.fileDescriptor
            state.fileDescriptor = nil
            return fd
        }) {
            ftruncate(fd, 0)
            flock(fd, LOCK_UN)
            close(fd)
            return
        }

        let fd = open(lockURL.path, O_WRONLY | O_CLOEXEC)
        guard fd >= 0 else { return }
        defer { close(fd) }

        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { return }
        defer { flock(fd, LOCK_UN) }
        ftruncate(fd, 0)
    }

    // MARK: Launchctl

    @discardableResult
    public func runLaunchctl(_ arguments: [String]) -> Int32 {
        run(executable: "/bin/launchctl", arguments: arguments)
    }

    // MARK: Executable Discovery

    public func findExecutable(_ name: String) -> String? {
        let knownPaths = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "/bin/\(name)",
        ]
        for path in knownPaths where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        guard let output = runCapturingOutput(executable: "/usr/bin/which", arguments: [name]),
            !output.isEmpty
        else { return nil }
        let resolved = URL(fileURLWithPath: output).standardizedFileURL.path
        guard FileManager.default.isExecutableFile(atPath: resolved) else { return nil }
        return resolved
    }

    // MARK: Subprocess Execution

    @discardableResult
    public func run(executable: String, arguments: [String]) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return -1 }
        task.waitUntilExit()
        return task.terminationStatus
    }

    public func runCapturingOutput(executable: String, arguments: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return nil }
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func runStreaming(executable: String, arguments: [String]) -> AsyncStream<String> {
        AsyncStream { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: executable)
            task.arguments = arguments
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice

            guard (try? task.run()) != nil else {
                continuation.finish()
                return
            }

            continuation.onTermination = { _ in task.terminate() }

            let reader = pipe.fileHandleForReading
            DispatchQueue.global().async {
                var buffer = Data()
                let newline = UInt8(ascii: "\n")
                while true {
                    let chunk = reader.readData(ofLength: 4096)
                    guard !chunk.isEmpty else { break }
                    buffer.append(chunk)

                    while let newlineIndex = buffer.firstIndex(of: newline) {
                        let lineData = buffer[..<newlineIndex]
                        if let line = String(data: Data(lineData), encoding: .utf8) {
                            continuation.yield(line)
                        }
                        buffer.removeSubrange(...newlineIndex)
                    }
                }
                if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) {
                    continuation.yield(line)
                }
                continuation.finish()
            }
        }
    }
}

// MARK: - Private

extension DarwinGateway {
    private var lockURL: URL {
        lockDirectory.appendingPathComponent("lyra.pid")
    }
}

extension timeval {
    fileprivate var fractionalSeconds: Double {
        Double(tv_sec) + Double(tv_usec) / 1_000_000
    }
}
