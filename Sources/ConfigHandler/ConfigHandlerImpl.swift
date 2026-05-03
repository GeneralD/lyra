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
        guard let editor = editorProvider(), !editor.isEmpty else {
            return .failure(.failed(detail: "$EDITOR is not set. Set it with: export EDITOR=vim"))
        }

        return launchConfig { path in
            @Dependency(\.processGateway) var processGateway
            return processGateway.run(
                executable: "/bin/sh",
                arguments: ["-c", "exec \(editor) \"$1\"", "lyra-config-edit", path]
            )
        } failureDetail: {
            "Editor command failed with exit status \($0)"
        }
    }

    public func openConfig() -> ConfigLaunchResult {
        launchConfig { path in
            @Dependency(\.processGateway) var processGateway
            return processGateway.run(executable: "/usr/bin/open", arguments: [path])
        } failureDetail: {
            "Open command failed with exit status \($0)"
        }
    }

    private func launchConfig(
        using launcher: (String) -> Int32,
        failureDetail: (Int32) -> String
    ) -> ConfigLaunchResult {
        switch configPath() {
        case .success(.found(let path)):
            let status = launcher(path)
            return status == 0 ? .success(.launched(path: path)) : .failure(.failed(detail: failureDetail(status)))
        case .failure(let error):
            return .failure(error)
        }
    }
}
