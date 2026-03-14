import Foundation

public enum LaunchAgentManager {
    private static let label = "com.generald.backdrop"

    private static var plistPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    public static func install() throws {
        let resolvedPath = installedPath()
            ?? URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0]).standardizedFileURL.path
        let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
            "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key><string>\(label)</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(resolvedPath)</string>
                    <string>daemon</string>
                </array>
                <key>RunAtLoad</key><true/>
            </dict>
            </plist>
            """

        ProcessManager.stopExisting()

        let uid = getuid()
        let target = "gui/\(uid)"

        // Bootout first in case already registered
        runLaunchctl(["bootout", "\(target)/\(label)"])

        try plist.write(to: plistPath, atomically: true, encoding: .utf8)

        let status = runLaunchctl(["bootstrap", target, plistPath.path])
        guard status == 0 else {
            throw LaunchAgentError.bootstrapFailed(status)
        }
        print("Installed and started: \(plistPath.path)")
    }

    public static func uninstall() throws {
        guard FileManager.default.fileExists(atPath: plistPath.path) else {
            print("Not installed")
            return
        }
        let uid = getuid()
        runLaunchctl(["bootout", "gui/\(uid)/\(label)"])
        ProcessManager.stopExisting()
        try FileManager.default.removeItem(at: plistPath)
        print("Uninstalled")
    }

    @discardableResult
    private static func runLaunchctl(_ arguments: [String]) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = arguments
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
        return task.terminationStatus
    }
}

extension LaunchAgentManager {
    private static func installedPath() -> String? {
        let binaryName = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [binaryName]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        guard let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else { return nil }
        let resolved = URL(fileURLWithPath: output).standardizedFileURL.path
        guard FileManager.default.isExecutableFile(atPath: resolved) else { return nil }
        return resolved
    }
}

enum LaunchAgentError: Error {
    case bootstrapFailed(Int32)
}
