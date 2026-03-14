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
