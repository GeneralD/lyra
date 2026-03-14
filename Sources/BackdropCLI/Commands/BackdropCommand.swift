import ArgumentParser

public struct BackdropCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "backdrop",
        abstract: "Desktop backdrop — lyrics overlay, video wallpaper, and more",
        subcommands: [
            StartCommand.self,
            StopCommand.self,
            RestartCommand.self,
            ServiceCommand.self,
            CompletionCommand.self,
            DaemonCommand.self,
        ],
        defaultSubcommand: StartCommand.self
    )

    public init() {}
}
