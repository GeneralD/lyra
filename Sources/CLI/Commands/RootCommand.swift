import ArgumentParser
import Foundation

private let appVersion: String = {
    guard let url = Bundle.module.url(forResource: "version", withExtension: "txt"),
          let content = try? String(contentsOf: url, encoding: .utf8) else { return "unknown" }
    return content.trimmingCharacters(in: .whitespacesAndNewlines)
}()

public struct RootCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
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
        ],
        defaultSubcommand: StartCommand.self
    )

    public init() {}
}

struct VersionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "version",
        abstract: "Show version"
    )

    func run() {
        print(RootCommand.configuration.version ?? "unknown")
    }
}
