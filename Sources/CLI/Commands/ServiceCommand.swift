import ArgumentParser
import Dependencies
import Domain

struct ServiceCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "service",
        abstract: "Manage login item service",
        subcommands: [Install.self, Uninstall.self]
    )

    struct Install: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Register as login item (LaunchAgent)"
        )

        func run() throws {
            @Dependency(\.serviceHandler) var handler
            @Dependency(\.standardOutput) var output
            switch handler.install() {
            case .success(let s): output.output(s)
            case .failure(let e):
                output.output(e)
                throw ExitCode.failure
            }
        }
    }

    struct Uninstall: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Remove login item"
        )

        func run() throws {
            @Dependency(\.serviceHandler) var handler
            @Dependency(\.standardOutput) var output
            switch handler.uninstall() {
            case .success(let s): output.output(s)
            case .failure(let e):
                output.output(e)
                throw ExitCode.failure
            }
        }
    }
}
