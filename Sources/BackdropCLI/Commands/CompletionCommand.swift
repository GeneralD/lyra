import ArgumentParser

struct CompletionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "completion",
        abstract: "Output shell completion script"
    )

    @Argument(help: "Shell type (zsh, bash)")
    var shell: String

    func run() throws {
        switch shell.lowercased() {
        case "zsh":
            print(Self.zshCompletion)
        case "bash":
            print(Self.bashCompletion)
        default:
            throw ValidationError("Unsupported shell: \(shell). Use 'zsh' or 'bash'.")
        }
    }

    private static let zshCompletion = """
        #compdef backdrop

        _backdrop() {
            local -a commands
            commands=(
                'start:Start the overlay as a background process'
                'stop:Stop the running overlay'
                'restart:Stop and start the overlay'
                'service:Manage login item service'
                'completion:Output shell completion script'
            )

            local -a service_commands
            service_commands=(
                'install:Register as login item (LaunchAgent)'
                'uninstall:Remove login item'
            )

            local -a completion_commands
            completion_commands=(
                'zsh:Output zsh completion script'
                'bash:Output bash completion script'
            )

            _arguments -C '1:command:->cmd' '*::arg:->args'

            case $state in
            cmd)
                _describe 'command' commands
                ;;
            args)
                case $words[1] in
                service)
                    _describe 'subcommand' service_commands
                    ;;
                completion)
                    _describe 'shell' completion_commands
                    ;;
                esac
                ;;
            esac
        }

        _backdrop "$@"
        """

    private static let bashCompletion = """
        _backdrop() {
            local cur prev commands service_cmds completion_cmds
            COMPREPLY=()
            cur="${COMP_WORDS[COMP_CWORD]}"
            prev="${COMP_WORDS[COMP_CWORD-1]}"

            commands="start stop restart service completion"
            service_cmds="install uninstall"
            completion_cmds="zsh bash"

            case "$prev" in
            backdrop)
                COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
                ;;
            service)
                COMPREPLY=( $(compgen -W "$service_cmds" -- "$cur") )
                ;;
            completion)
                COMPREPLY=( $(compgen -W "$completion_cmds" -- "$cur") )
                ;;
            esac
        }

        complete -F _backdrop backdrop
        """
}
