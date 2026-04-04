import Foundation

public enum ProcessManager {
    public static func findOverlayPIDs() -> [Int32] {
        let myPID = ProcessInfo.processInfo.processIdentifier
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-f", "lyra"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .split(separator: "\n")
            .compactMap { Int32($0) }
            .filter { $0 != myPID } ?? []
    }

    @discardableResult
    public static func stopExisting() -> Bool {
        let pids = findOverlayPIDs()
        guard !pids.isEmpty else { return false }

        for pid in pids { kill(pid, SIGTERM) }
        for _ in 0..<20 {
            guard pids.contains(where: { kill($0, 0) == 0 }) else { break }
            usleep(100_000)
        }
        for pid in pids where kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        usleep(100_000)
        ProcessLock.shared.cleanup()

        // Wait for flock to be released (kernel cleanup after process death)
        for _ in 0..<20 {
            guard ProcessLock.shared.isLocked else { return true }
            usleep(100_000)
        }
        return !ProcessLock.shared.isLocked
    }
}
