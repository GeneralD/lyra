import Dependencies
import Domain
import Files
import Foundation

public struct ServiceHandlerImpl: ServiceHandler {
    public init() {}
    private let label = "com.generald.lyra"
    private let homebrewLabel = "homebrew.mxcl.lyra"
}

extension ServiceHandlerImpl {
    private var launchAgentsFolder: Folder {
        get throws { try Folder.home.subfolder(at: "Library/LaunchAgents") }
    }

    private var plistFile: File? {
        try? launchAgentsFolder.file(named: "\(label).plist")
    }

    private var homebrewPlistFile: File? {
        try? launchAgentsFolder.file(named: "\(homebrewLabel).plist")
    }

    public func install() -> ServiceInstallResult {
        guard homebrewPlistFile == nil else { return .failure(.managedByHomebrew) }

        let plistDict: [String: Any] = [
            "Label": label,
            "ProgramArguments": programArguments,
            "RunAtLoad": true,
        ]
        guard
            let plistData = try? PropertyListSerialization.data(
                fromPropertyList: plistDict, format: .xml, options: 0
            )
        else { return .failure(.failed(detail: "Failed to serialize plist")) }

        @Dependency(\.processHandler) var processHandler
        _ = processHandler.stop()

        let uid = getuid()
        let target = "gui/\(uid)"

        runLaunchctl(["bootout", "\(target)/\(label)"])

        guard let folder = try? launchAgentsFolder,
            let file = try? folder.createFile(named: "\(label).plist"),
            (try? file.write(plistData)) != nil
        else { return .failure(.failed(detail: "Failed to write plist file")) }

        let status = runLaunchctl(["bootstrap", target, file.path])
        guard status == 0 else { return .failure(.bootstrapFailed(status: status)) }
        return .success(.installed(path: file.path))
    }

    public func uninstall() -> ServiceUninstallResult {
        guard let file = plistFile else {
            return homebrewPlistFile != nil ? .failure(.managedByHomebrew) : .failure(.notInstalled)
        }
        let uid = getuid()
        runLaunchctl(["bootout", "gui/\(uid)/\(label)"])

        @Dependency(\.processHandler) var processHandler
        _ = processHandler.stop()

        guard (try? file.delete()) != nil else {
            return .failure(.failed(detail: "Failed to delete plist file"))
        }
        return .success(.uninstalled)
    }
}

extension ServiceHandlerImpl {
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
        URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0]).standardizedFileURL
            .path
    }

    @discardableResult
    fileprivate func runLaunchctl(_ arguments: [String]) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = arguments
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return -1 }
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
