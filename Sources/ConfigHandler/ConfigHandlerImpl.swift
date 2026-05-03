import Dependencies
import Domain
import Foundation

public struct ConfigHandlerImpl {
    private let editorProvider: @Sendable () -> String?

    public init(
        editorProvider: @escaping @Sendable () -> String? = { ProcessInfo.processInfo.environment["EDITOR"] }
    ) {
        self.editorProvider = editorProvider
    }
}

extension ConfigHandlerImpl: ConfigHandler {
    public func template(format: ConfigFormat) -> String? {
        @Dependency(\.configUseCase) var configUseCase
        return configUseCase.template(format: format)
    }

    public func writeTemplate(format: ConfigFormat, force: Bool) -> ConfigWriteResult {
        @Dependency(\.configUseCase) var configUseCase
        guard let path = try? configUseCase.writeTemplate(format: format, force: force) else {
            return .failure(.failed(detail: "Failed to write config file"))
        }
        return .success(.created(path: path))
    }

    public func configPath() -> ConfigPathResult {
        @Dependency(\.configUseCase) var configUseCase

        if let existing = configUseCase.existingConfigPath {
            return .success(.found(path: existing))
        }
        switch writeTemplate(format: .toml, force: false) {
        case .success(.created(let path)): return .success(.found(path: path))
        case .failure(let error): return .failure(error)
        }
    }

    public func editConfig() -> ConfigLaunchResult {
        guard let editor = editorProvider() else {
            return .failure(.failed(detail: "$EDITOR is not set. Set it with: export EDITOR=vim"))
        }

        @Dependency(\.processGateway) var processGateway
        switch EditorInvocation.parsed(from: editor, executableResolver: processGateway.findExecutable) {
        case .success(let command):
            return launchConfig { path in
                processGateway.runInteractive(
                    executable: command.executable,
                    arguments: command.arguments + [path]
                )
            } exitFailureDetail: {
                "Editor command failed with exit status \($0)"
            } launchFailureDetail: {
                "Editor process failed to launch"
            }
        case .failure(let error):
            return .failure(error)
        }
    }

    public func openConfig() -> ConfigLaunchResult {
        launchConfig { path in
            @Dependency(\.processGateway) var processGateway
            return processGateway.runInteractive(executable: "/usr/bin/open", arguments: [path])
        } exitFailureDetail: {
            "Open command failed with exit status \($0)"
        } launchFailureDetail: {
            "Open process failed to launch"
        }
    }

    private func launchConfig(
        using launcher: (String) -> Int32,
        exitFailureDetail: (Int32) -> String,
        launchFailureDetail: () -> String
    ) -> ConfigLaunchResult {
        switch configPath() {
        case .success(.found(let path)):
            let status = launcher(path)
            switch status {
            case 0:
                return .success(.launched(path: path))
            case -1:
                return .failure(.failed(detail: launchFailureDetail()))
            default:
                return .failure(.failed(detail: exitFailureDetail(status)))
            }
        case .failure(let error):
            return .failure(error)
        }
    }
}
