import ArgumentParser

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
            try LaunchAgentManager().install()
        }
    }

    struct Uninstall: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Remove login item"
        )

        func run() throws {
            try LaunchAgentManager().uninstall()
        }
    }
}
