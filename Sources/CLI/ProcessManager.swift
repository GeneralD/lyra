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

        pids.forEach { kill($0, SIGTERM) }
        for _ in 0 ..< 20 {
            guard pids.contains(where: { kill($0, 0) == 0 }) else { break }
            usleep(100_000)
        }
        pids.filter { kill($0, 0) == 0 }.forEach { kill($0, SIGKILL) }
        usleep(100_000)
        return true
    }
}
