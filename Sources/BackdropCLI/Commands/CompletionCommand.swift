import ArgumentParser
import Foundation

struct CompletionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "completion",
        abstract: "Output shell completion script"
    )

    @Argument(help: "Shell type (zsh, bash)")
    var shell: String

    func run() throws {
        guard let url = Bundle.module.url(forResource: "backdrop", withExtension: shell.lowercased()),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            throw ValidationError("Unsupported shell: \(shell). Use 'zsh' or 'bash'.")
        }
        print(content)
    }
}
