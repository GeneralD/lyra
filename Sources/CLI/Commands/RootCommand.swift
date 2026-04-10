import ArgumentParser

@main
struct RootCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lyra",
        abstract: "Desktop lyrics overlay, video wallpaper, and more",
        version: appVersion,
        subcommands: [
            StartCommand.self,
            StopCommand.self,
            RestartCommand.self,
            ServiceCommand.self,
            CompletionCommand.self,
            VersionCommand.self,
            DaemonCommand.self,
            HealthcheckCommand.self,
            ConfigCommand.self,
            TrackCommand.self,
            BenchmarkCommand.self,
        ],
        defaultSubcommand: StartCommand.self
    )
}
