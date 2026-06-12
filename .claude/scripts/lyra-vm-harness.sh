#!/usr/bin/env bash
# lyra-vm-harness.sh — UTM macOS guest verification harness for lyra
#
# Primary path: SSH.  utmctl is used only for VM lifecycle (start/stop/reboot).
# All build, install, run, and artifact operations go over SSH.
#
# NOTE: utmctl ip-address and utmctl exec are NOT supported by the macOS
# Apple Virtualization Framework backend (only QEMU supports them).
# Set LYRA_VM_SSH_HOST to the guest's static/bridge IP to bypass utmctl IP lookup.
#
# Prerequisites: see .claude/rules/vm-verification.md
#
# Usage:
#   lyra-vm-harness.sh boot       <vm>            # Start VM, wait for SSH
#   lyra-vm-harness.sh shutdown  <vm>            # Clean guest shutdown
#   lyra-vm-harness.sh reboot    <vm>            # Guest reboot, wait for SSH
#   lyra-vm-harness.sh run-lyra  <vm>            # Build (host), push binary, install, start
#   lyra-vm-harness.sh capture   <vm> [out-dir]  # Screenshot + logs + process sample
#   lyra-vm-harness.sh restore   <vm>            # Restore lyra service to prior state
#   lyra-vm-harness.sh play-music <vm> [url]     # Open URL in Safari + auto-play (MediaRemote test)
#   lyra-vm-harness.sh exec      <vm> -- <cmd>   # Run arbitrary command via SSH
#   lyra-vm-harness.sh ip        <vm>            # Print guest IP

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — override via environment variables
# ---------------------------------------------------------------------------
: "${LYRA_VM_SSH_USER:=admin}"
: "${LYRA_VM_SSH_KEY:=$HOME/.ssh/vm_rsa}"
: "${LYRA_VM_SSH_PORT:=22}"
: "${LYRA_VM_BOOT_TIMEOUT:=120}"   # seconds to wait for SSH after utmctl start

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
: "${LYRA_VM_ARTIFACTS_DIR:=/tmp/lyra-vm-artifacts-${TIMESTAMP}}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { printf '[lyra-vm] %s\n' "$*" >&2; }
die()  { log "ERROR: $*"; exit 1; }

vm_ip() {
    # LYRA_VM_SSH_HOST overrides utmctl IP lookup (required for Apple Virtualization backend
    # where utmctl ip-address is unsupported — only works for QEMU backend VMs).
    if [[ -n "${LYRA_VM_SSH_HOST:-}" ]]; then
        printf '%s\n' "$LYRA_VM_SSH_HOST"
        return 0
    fi
    utmctl ip-address "$1" 2>/dev/null | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1
}

# ssh_run <ip> <cmd>  — run a command on the guest over SSH
ssh_run() {
    local ip="$1"; shift
    ssh -i "$LYRA_VM_SSH_KEY" \
        -p "$LYRA_VM_SSH_PORT" \
        -o StrictHostKeyChecking=no \
        -o BatchMode=yes \
        -o ConnectTimeout=10 \
        "${LYRA_VM_SSH_USER}@${ip}" "$@"
}

# scp_get <ip> <remote-path> <local-path>
scp_get() {
    local ip="$1" remote="$2" local_path="$3"
    scp -i "$LYRA_VM_SSH_KEY" \
        -P "$LYRA_VM_SSH_PORT" \
        -o StrictHostKeyChecking=no \
        -o BatchMode=yes \
        "${LYRA_VM_SSH_USER}@${ip}:${remote}" "$local_path"
}

# scp_put <ip> <local-path> <remote-path>
scp_put() {
    local ip="$1" local_path="$2" remote="$3"
    scp -i "$LYRA_VM_SSH_KEY" \
        -P "$LYRA_VM_SSH_PORT" \
        -o StrictHostKeyChecking=no \
        -o BatchMode=yes \
        "$local_path" "${LYRA_VM_SSH_USER}@${ip}:${remote}"
}

# scp_put_r <ip> <local-dir> <remote-parent-dir>  — recursive directory copy
scp_put_r() {
    local ip="$1" local_dir="$2" remote_parent="$3"
    scp -r -i "$LYRA_VM_SSH_KEY" \
        -P "$LYRA_VM_SSH_PORT" \
        -o StrictHostKeyChecking=no \
        -o BatchMode=yes \
        "$local_dir" "${LYRA_VM_SSH_USER}@${ip}:${remote_parent}"
}

wait_for_ssh() {
    local vm="$1"
    local deadline=$((SECONDS + LYRA_VM_BOOT_TIMEOUT))
    local ip=""
    log "Waiting for $vm to be reachable via SSH (timeout: ${LYRA_VM_BOOT_TIMEOUT}s)..."
    while [[ $SECONDS -lt $deadline ]]; do
        ip="$(vm_ip "$vm")"
        if [[ -n "$ip" ]] && ssh_run "$ip" exit 0 2>/dev/null; then
            log "SSH ready at $ip"
            echo "$ip"
            return 0
        fi
        sleep 5
    done
    die "Timed out waiting for SSH on $vm"
}

require_vm() {
    [[ -n "${1:-}" ]] || die "VM name required"
}

# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------

cmd_boot() {
    local vm="${1:-}"; require_vm "$vm"
    log "Starting $vm..."
    utmctl start "$vm"
    wait_for_ssh "$vm"
}

cmd_shutdown() {
    local vm="${1:-}"; require_vm "$vm"
    local ip; ip="$(vm_ip "$vm")" || die "Cannot determine IP for $vm — is it running?"
    log "Shutting down $vm gracefully..."
    # Ask the guest to shut down; fall back to utmctl stop if SSH fails
    ssh_run "$ip" "sudo shutdown -h now" 2>/dev/null || true
    sleep 5
    if [[ "$(utmctl status "$vm" 2>/dev/null)" != "stopped" ]]; then
        log "Guest did not stop cleanly — forcing stop via utmctl"
        utmctl stop "$vm" --kill 2>/dev/null || true
    fi
    log "$vm stopped."
}

cmd_reboot() {
    local vm="${1:-}"; require_vm "$vm"
    local ip; ip="$(vm_ip "$vm")" || die "Cannot determine IP for $vm"
    log "Rebooting $vm..."
    ssh_run "$ip" "sudo reboot" 2>/dev/null || true
    sleep 10  # allow the guest time to begin rebooting before polling
    wait_for_ssh "$vm"
}

cmd_run_lyra() {
    local vm="${1:-}"; require_vm "$vm"
    local ip; ip="$(vm_ip "$vm")" || die "Cannot determine IP for $vm"

    log "Building lyra release binary on host..."
    (cd "$REPO_ROOT" && swift build -c release)

    local binary="$REPO_ROOT/.build/release/lyra"
    [[ -f "$binary" ]] || die "Build succeeded but binary not found at $binary"

    log "Pushing binary to guest..."
    ssh_run "$ip" "sudo rm -rf /tmp/lyra-drop && mkdir -p /tmp/lyra-drop"
    scp_put "$ip" "$binary" "/tmp/lyra-drop/lyra"

    log "Pushing resource bundles to guest..."
    local bundle_dir
    for bundle_dir in "$REPO_ROOT"/.build/release/*.bundle; do
        [[ -d "$bundle_dir" ]] || continue
        scp_put_r "$ip" "$bundle_dir" "/tmp/lyra-drop/"
    done

    log "Installing on guest..."
    ssh_run "$ip" "sudo install -m 755 /tmp/lyra-drop/lyra /usr/local/bin/lyra"
    ssh_run "$ip" "for b in /tmp/lyra-drop/*.bundle; do [ -d \"\$b\" ] && sudo cp -r \"\$b\" /usr/local/bin/; done"

    log "Saving current lyra service state on guest..."
    local prior_state
    prior_state="$(ssh_run "$ip" "brew services list 2>/dev/null | grep '^lyra' | awk '{print \$2}'" 2>/dev/null || echo "none")"
    # Persist state so restore subcommand can read it back
    ssh_run "$ip" "printf '%s\n' '$prior_state' > ~/.lyra-vm-prior-service-state"

    log "Stopping any running lyra instance (KeepAlive bootout + direct kill)..."
    ssh_run "$ip" "brew services stop lyra 2>/dev/null || true"
    # Kill any leftover daemon (e.g. from a previous run-lyra that wasn't restored).
    # pgrep -x matches the binary name exactly to avoid killing unrelated processes.
    ssh_run "$ip" "pid=\$(pgrep -x lyra | head -1); [ -n \"\$pid\" ] && kill \"\$pid\" 2>/dev/null; sleep 1" 2>/dev/null || true

    log "Starting lyra daemon on guest (GUI session via launchctl asuser)..."
    # Write a launcher script on the guest so quoting stays simple.
    # sudo launchctl asuser injects the command into the logged-in user's GUI
    # bootstrap namespace — required for AppKit windows to appear on the guest
    # display.  nohup alone spawns in the SSH bootstrap context where WindowServer
    # is inaccessible.  sudo is required; launchctl asuser cannot switch audit
    # sessions from an SSH session without elevated privileges.
    # Use 'echo' for PID capture — avoids the printf \n quoting trap where an
    # unquoted \n in sh is consumed by the shell and becomes literal 'n'.
    ssh_run "$ip" "printf '#!/bin/sh\nnohup /usr/local/bin/lyra daemon > \"\$HOME\"/.lyra-vm-daemon.log 2>&1 &\necho \"\$!\" > \"\$HOME\"/.lyra-vm-daemon.pid\n' > /tmp/lyra-vm-launch.sh && chmod +x /tmp/lyra-vm-launch.sh"
    ssh_run "$ip" "sudo launchctl asuser \$(id -u) /tmp/lyra-vm-launch.sh"
    sleep 3

    local pid
    pid="$(ssh_run "$ip" "cat ~/.lyra-vm-daemon.pid 2>/dev/null || printf '?'")"
    log "lyra daemon running on guest (PID=$pid)"
}

cmd_capture() {
    local vm="${1:-}"; require_vm "$vm"
    local out_dir="${2:-$LYRA_VM_ARTIFACTS_DIR}"
    local ip; ip="$(vm_ip "$vm")" || die "Cannot determine IP for $vm"

    mkdir -p "$out_dir"
    log "Collecting artifacts from $vm -> $out_dir"

    # Screenshot — requires a logged-in GUI session on the guest
    if ssh_run "$ip" "screencapture -x /tmp/lyra-vm-screenshot.png" 2>/dev/null; then
        scp_get "$ip" "/tmp/lyra-vm-screenshot.png" "$out_dir/screenshot.png" && \
            log "  screenshot -> $out_dir/screenshot.png"
    else
        log "  WARNING: screencapture failed (no GUI display session on guest?)"
    fi

    # Unified log — lyra subsystem, last 10 minutes
    if ssh_run "$ip" \
        "log show --last 10m --predicate 'subsystem CONTAINS \"lyra\" OR process == \"lyra\"' 2>/dev/null" \
        > "$out_dir/unified.log"; then
        log "  unified log -> $out_dir/unified.log"
    else
        log "  WARNING: log show failed"
    fi

    # Process sample — 5 seconds
    # note: `sample` requires sudo to sample other users' processes on macOS
    if ssh_run "$ip" "pid=\"\$(pgrep -x lyra | head -1)\"; \
        if [ -n \"\$pid\" ]; then sudo sample \"\$pid\" 5 -f /tmp/lyra-vm-sample.txt 2>/dev/null; \
        else printf 'lyra not running\n' > /tmp/lyra-vm-sample.txt; fi" 2>/dev/null && \
        scp_get "$ip" "/tmp/lyra-vm-sample.txt" "$out_dir/process-sample.txt"; then
        log "  process sample -> $out_dir/process-sample.txt"
    else
        log "  WARNING: process sample failed"
    fi

    # Daemon log written by run-lyra
    # shellcheck disable=SC2088  # ~ is in a remote scp path and intentionally expands on the guest
    if scp_get "$ip" "~/.lyra-vm-daemon.log" "$out_dir/daemon.log" 2>/dev/null; then
        log "  daemon log -> $out_dir/daemon.log"
    else
        log "  (no daemon.log — daemon may not have been started via run-lyra)"
    fi

    log "Artifacts collected in $out_dir"
    printf '%s\n' "$out_dir"
}

cmd_restore() {
    local vm="${1:-}"; require_vm "$vm"
    local ip; ip="$(vm_ip "$vm")" || die "Cannot determine IP for $vm"

    # Stop the daemon we started, if any
    ssh_run "$ip" "pid=\"\$(cat ~/.lyra-vm-daemon.pid 2>/dev/null)\"; \
        [ -n \"\$pid\" ] && kill \"\$pid\" 2>/dev/null; rm -f ~/.lyra-vm-daemon.pid" \
        2>/dev/null || true

    # Restore brew service to its prior state
    local prior_state
    prior_state="$(ssh_run "$ip" "cat ~/.lyra-vm-prior-service-state 2>/dev/null || printf 'none'")"
    if [[ "$prior_state" == "started" ]]; then
        log "Restoring lyra brew service on guest..."
        ssh_run "$ip" "brew services start lyra"
    else
        log "Prior state was '$prior_state' — leaving brew service stopped"
    fi
    ssh_run "$ip" "rm -f ~/.lyra-vm-prior-service-state"
    log "Restore complete."
}

cmd_play_music() {
    local vm="${1:-}"; require_vm "$vm"
    local url="${2:-https://www.youtube.com/watch?v=jNQXAC9IVRw}"
    local ip; ip="$(vm_ip "$vm")" || die "Cannot determine IP for $vm"

    log "Opening $url in Safari on guest..."
    ssh_run "$ip" "open -a Safari '$url'"
    sleep 10

    log "Injecting play via AppleScript..."
    # Enable JavaScript from Apple Events if not already set
    ssh_run "$ip" "defaults write com.apple.Safari AllowJavaScriptFromAppleEvents 1" 2>/dev/null || true
    ssh_run "$ip" "osascript -e 'tell application \"Safari\" to tell window 1 to tell current tab to do JavaScript \"document.querySelectorAll(\\\"video,audio\\\").forEach(function(m){try{m.play()}catch(e){}})\"'"

    sleep 5
    log "Playback started — MediaRemote should now see it. Run: $0 exec $vm -- lyra track"
}

cmd_exec() {
    local vm="${1:-}"; require_vm "$vm"; shift
    [[ "${1:-}" == "--" ]] && shift
    [[ $# -gt 0 ]] || die "No command supplied after exec"
    local ip; ip="$(vm_ip "$vm")" || die "Cannot determine IP for $vm"
    ssh_run "$ip" "$@"
}

cmd_ip() {
    local vm="${1:-}"; require_vm "$vm"
    local ip; ip="$(vm_ip "$vm")"
    [[ -n "$ip" ]] || die "Could not determine IP for $vm (not running or guest agent unavailable)"
    printf '%s\n' "$ip"
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
SUBCOMMAND="${1:-}"; shift || true

case "$SUBCOMMAND" in
    boot)     cmd_boot     "$@" ;;
    shutdown) cmd_shutdown "$@" ;;
    reboot)   cmd_reboot   "$@" ;;
    run-lyra) cmd_run_lyra "$@" ;;
    capture)  cmd_capture  "$@" ;;
    restore)     cmd_restore    "$@" ;;
    play-music)  cmd_play_music "$@" ;;
    exec)        cmd_exec       "$@" ;;
    ip)       cmd_ip       "$@" ;;
    "")       die "Subcommand required. See .claude/rules/vm-verification.md for usage." ;;
    *)        die "Unknown subcommand: $SUBCOMMAND" ;;
esac
