import ArgumentParser

struct CompletionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "completion",
        abstract: "Output shell completion script"
    )

    @Argument(help: "Shell type (zsh, bash, fish)")
    var shell: String

    func run() throws {
        guard let shell = CompletionShell(rawValue: shell.lowercased()) else {
            throw ValidationError("Unsupported shell: \(self.shell). Use 'zsh', 'bash', or 'fish'.")
        }
        let script = RootCommand.completionScript(for: shell)
        print(script)
    }
}
