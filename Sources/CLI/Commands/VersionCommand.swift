import ArgumentParser

struct VersionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "version",
        abstract: "Show version"
    )

    func run() {
        print(RootCommand.configuration.version)
    }
}
