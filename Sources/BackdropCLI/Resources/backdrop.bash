_backdrop() {
    local cur prev commands service_cmds completion_cmds
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    commands="start stop restart service completion --version"
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
