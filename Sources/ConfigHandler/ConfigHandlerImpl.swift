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
        switch EditorCommand.parsed(from: editor, executableResolver: processGateway.findExecutable) {
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

private struct EditorCommand: Equatable {
    var executable: String
    var arguments: [String]

    static func parsed(
        from source: String,
        executableResolver: (String) -> String?
    ) -> Result<EditorCommand, ConfigFailure> {
        guard source.rangeOfCharacter(from: .newlines) == nil else {
            return .failure(.failed(detail: "$EDITOR must not contain newline characters"))
        }

        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(.failed(detail: "$EDITOR is not set. Set it with: export EDITOR=vim"))
        }

        switch words(from: trimmed) {
        case .success(let words):
            guard let executableName = words.first, !executableName.isEmpty else {
                return .failure(.failed(detail: "$EDITOR does not contain an executable command"))
            }

            let executable: String
            if executableName.contains("/") {
                executable = executableName
            } else if let resolved = executableResolver(executableName) {
                executable = resolved
            } else {
                return .failure(.failed(detail: "Editor executable not found: \(executableName)"))
            }

            return .success(Self(executable: executable, arguments: Array(words.dropFirst())))
        case .failure(let error):
            return .failure(error)
        }
    }

    private static func words(from source: String) -> Result<[String], ConfigFailure> {
        var words: [String] = []
        var word = ""
        var quotedBy: Character?
        var escaping = false
        var hasWord = false

        for character in source {
            if escaping {
                word.append(character)
                escaping = false
                hasWord = true
                continue
            }

            if let quote = quotedBy {
                if character == quote {
                    quotedBy = nil
                    hasWord = true
                } else if quote == "\"", character == "\\" {
                    escaping = true
                    hasWord = true
                } else {
                    word.append(character)
                    hasWord = true
                }
                continue
            }

            if character == "\\" {
                escaping = true
                hasWord = true
            } else if character == "'" || character == "\"" {
                quotedBy = character
                hasWord = true
            } else if isWhitespace(character) {
                if hasWord {
                    words.append(word)
                    word = ""
                    hasWord = false
                }
            } else {
                word.append(character)
                hasWord = true
            }
        }

        guard !escaping else {
            return .failure(.failed(detail: "$EDITOR ends with an unfinished escape"))
        }
        guard quotedBy == nil else {
            return .failure(.failed(detail: "$EDITOR contains an unclosed quote"))
        }
        if hasWord {
            words.append(word)
        }
        return .success(words)
    }

    private static func isWhitespace(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.whitespaces.contains($0) }
    }
}
