import ArgumentParser
import Dependencies
import Domain
import Entity
import Foundation

struct ConfigCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Manage configuration",
        subcommands: [
            ConfigTemplateCommand.self,
            ConfigInitCommand.self,
            ConfigEditCommand.self,
            ConfigOpenCommand.self,
        ]
    )
}

// MARK: - template

struct ConfigTemplateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "template",
        abstract: "Print config template to stdout"
    )

    @Option(name: .long, help: "Output format (toml or json)")
    var format: ConfigFormat = .toml

    func run() throws {
        @Dependency(\.configUseCase) var configUseCase
        guard let output = configUseCase.template(format: format) else {
            throw ValidationError("Failed to generate template")
        }
        print(output)
    }
}

// MARK: - init

struct ConfigInitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Create config file with default values"
    )

    @Option(name: .long, help: "Output format (toml or json)")
    var format: ConfigFormat = .toml

    @Flag(name: .long, help: "Overwrite existing config file")
    var force = false

    func run() throws {
        @Dependency(\.configUseCase) var configUseCase
        let path = try configUseCase.writeTemplate(format: format, force: force)
        print("Config file created at \(path)")
    }
}

// MARK: - edit

struct ConfigEditCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "edit",
        abstract: "Open config file in $EDITOR"
    )

    func run() throws {
        @Dependency(\.configDataSource) var dataSource

        let path: String
        if let existing = dataSource.existingConfigPath() {
            path = existing
        } else {
            @Dependency(\.configUseCase) var configUseCase
            path = try configUseCase.writeTemplate(format: .toml, force: false)
        }

        guard let editor = ProcessInfo.processInfo.environment["EDITOR"] else {
            throw ValidationError("$EDITOR is not set. Set it with: export EDITOR=vim")
        }

        let escapedPath = path.replacingOccurrences(of: "'", with: "'\"'\"'")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "\(editor) '\(escapedPath)'"]
        try process.run()
        process.waitUntilExit()
    }
}

// MARK: - open

struct ConfigOpenCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "open",
        abstract: "Open config file in default GUI application"
    )

    func run() throws {
        @Dependency(\.configDataSource) var dataSource

        let path: String
        if let existing = dataSource.existingConfigPath() {
            path = existing
        } else {
            @Dependency(\.configUseCase) var configUseCase
            path = try configUseCase.writeTemplate(format: .toml, force: false)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [path]
        try process.run()
        process.waitUntilExit()
    }
}

// MARK: - ConfigFormat + ExpressibleByArgument

extension ConfigFormat: ExpressibleByArgument {}
