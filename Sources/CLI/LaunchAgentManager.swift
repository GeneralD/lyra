import Files
import Foundation

public struct LaunchAgentManager {
    private let label = "com.generald.lyra"
    private let homebrewLabel = "homebrew.mxcl.lyra"

    public init() {}
}

extension LaunchAgentManager {
    private var launchAgentsFolder: Folder {
        get throws { try Folder.home.subfolder(at: "Library/LaunchAgents") }
    }

    private var plistFile: File? {
        try? launchAgentsFolder.file(named: "\(label).plist")
    }

    private var homebrewPlistFile: File? {
        try? launchAgentsFolder.file(named: "\(homebrewLabel).plist")
    }

    func install() throws {
        guard homebrewPlistFile == nil else {
            print("Already managed by brew services. Run 'brew services stop lyra' first.")
            return
        }

        let plistDict: [String: Any] = [
            "Label": label,
            "ProgramArguments": programArguments,
            "RunAtLoad": true,
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plistDict, format: .xml, options: 0
        )

        ProcessManager.stopExisting()

        let uid = getuid()
        let target = "gui/\(uid)"

        runLaunchctl(["bootout", "\(target)/\(label)"])

        let folder = try launchAgentsFolder
        let file = try folder.createFile(named: "\(label).plist")
        try file.write(plistData)

        let status = runLaunchctl(["bootstrap", target, file.path])
        guard status == 0 else {
            throw LaunchAgentError.bootstrapFailed(status)
        }
        print("Installed and started: \(file.path)")
    }

    func uninstall() throws {
        guard let file = plistFile else {
            if homebrewPlistFile != nil {
                print("Managed by brew services. Run 'brew services stop lyra' instead.")
            } else {
                print("Not installed")
            }
            return
        }
        let uid = getuid()
        runLaunchctl(["bootout", "gui/\(uid)/\(label)"])
        ProcessManager.stopExisting()
        try file.delete()
        print("Uninstalled")
    }
}

extension LaunchAgentManager {
    fileprivate var programArguments: [String] {
        guard let mintPath = mintRunPath else {
            return [installedPath ?? currentExecutablePath, "daemon"]
        }
        return [mintPath, "run", "GeneralD/lyra", "daemon"]
    }

    fileprivate var mintRunPath: String? {
        guard currentExecutablePath.contains("/.mint/") else { return nil }
        return whichCommand("mint")
    }

    fileprivate var installedPath: String? {
        whichCommand(URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent)
    }

    fileprivate var currentExecutablePath: String {
        URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0]).standardizedFileURL.path
    }

    @discardableResult
    fileprivate func runLaunchctl(_ arguments: [String]) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = arguments
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
        return task.terminationStatus
    }

    fileprivate func whichCommand(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        guard
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !output.isEmpty
        else { return nil }
        let resolved = URL(fileURLWithPath: output).standardizedFileURL.path
        guard FileManager.default.isExecutableFile(atPath: resolved) else { return nil }
        return resolved
    }
}

enum LaunchAgentError: Error {
    case bootstrapFailed(Int32)
}
