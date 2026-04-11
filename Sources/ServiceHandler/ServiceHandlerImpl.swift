import Dependencies
import Domain
import Files
import Foundation

public struct ServiceHandlerImpl {
    private let label = "com.generald.lyra"
    private let homebrewLabel = "homebrew.mxcl.lyra"
    private let launchAgentsPath: String
    private let executablePathOverride: String?

    @Dependency(\.processGateway) private var gateway

    public init(launchAgentsPath: String = "~/Library/LaunchAgents") {
        self.init(launchAgentsPath: launchAgentsPath, executablePath: nil)
    }

    init(launchAgentsPath: String = "~/Library/LaunchAgents", executablePath: String? = nil) {
        self.launchAgentsPath = NSString(string: launchAgentsPath).expandingTildeInPath
        self.executablePathOverride = executablePath
    }
}

extension ServiceHandlerImpl: ServiceHandler {
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

        let uid = getuid()
        let target = "gui/\(uid)"

        gateway.runLaunchctl(["bootout", "\(target)/\(label)"])

        guard let folder = try? launchAgentsFolder,
            let file = try? folder.createFile(named: "\(label).plist"),
            (try? file.write(plistData)) != nil
        else { return .failure(.failed(detail: "Failed to write plist file")) }

        let status = gateway.runLaunchctl(["bootstrap", target, file.path])
        guard status == 0 else { return .failure(.bootstrapFailed(status: status)) }
        return .success(.installed(path: file.path))
    }

    public func uninstall() -> ServiceUninstallResult {
        guard let file = plistFile else {
            return homebrewPlistFile != nil ? .failure(.managedByHomebrew) : .failure(.notInstalled)
        }
        let uid = getuid()
        gateway.runLaunchctl(["bootout", "gui/\(uid)/\(label)"])

        guard (try? file.delete()) != nil else {
            return .failure(.failed(detail: "Failed to delete plist file"))
        }
        return .success(.uninstalled)
    }
}

extension ServiceHandlerImpl {
    private var launchAgentsFolder: Folder {
        get throws { try Folder(path: launchAgentsPath) }
    }

    private var plistFile: File? {
        try? launchAgentsFolder.file(named: "\(label).plist")
    }

    private var homebrewPlistFile: File? {
        try? launchAgentsFolder.file(named: "\(homebrewLabel).plist")
    }

    private var programArguments: [String] {
        guard let mintPath = mintRunPath else {
            return [installedPath ?? currentExecutablePath, "daemon"]
        }
        return [mintPath, "run", "GeneralD/lyra", "daemon"]
    }

    private var mintRunPath: String? {
        guard currentExecutablePath.contains("/.mint/") else { return nil }
        return gateway.findExecutable("mint")
    }

    private var installedPath: String? {
        gateway.findExecutable(URL(fileURLWithPath: currentExecutablePath).lastPathComponent)
    }

    private var currentExecutablePath: String {
        URL(fileURLWithPath: executablePathOverride ?? Bundle.main.executablePath ?? CommandLine.arguments[0])
            .standardizedFileURL
            .path
    }
}
