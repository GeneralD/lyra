import Foundation

public struct LaunchAgentManager {
    private let label = "com.generald.backdrop"

    public init() {}
}

extension LaunchAgentManager {
    private var plistPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    public func install() throws {
        let argsXML = programArguments
            .map { "            <string>\($0)</string>" }
            .joined(separator: "\n")
        let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
            "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key><string>\(label)</string>
                <key>ProgramArguments</key>
                <array>
            \(argsXML)
                </array>
                <key>RunAtLoad</key><true/>
            </dict>
            </plist>
            """

        ProcessManager.stopExisting()

        let uid = getuid()
        let target = "gui/\(uid)"

        runLaunchctl(["bootout", "\(target)/\(label)"])

        try plist.write(to: plistPath, atomically: true, encoding: .utf8)

        let status = runLaunchctl(["bootstrap", target, plistPath.path])
        guard status == 0 else {
            throw LaunchAgentError.bootstrapFailed(status)
        }
        print("Installed and started: \(plistPath.path)")
    }

    public func uninstall() throws {
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
}

extension LaunchAgentManager {
    private var programArguments: [String] {
        guard let mintPath = mintRunPath else {
            return [installedPath ?? currentExecutablePath, "daemon"]
        }
        return [mintPath, "run", "GeneralD/backdrop", "daemon"]
    }

    private var mintRunPath: String? {
        guard currentExecutablePath.contains("/.mint/") else { return nil }
        return whichCommand("mint")
    }

    private var installedPath: String? {
        whichCommand(URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent)
    }

    private var currentExecutablePath: String {
        URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0]).standardizedFileURL.path
    }

    @discardableResult
    private func runLaunchctl(_ arguments: [String]) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = arguments
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
        return task.terminationStatus
    }

    private func whichCommand(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
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
