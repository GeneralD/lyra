# VM Verification — lyra UTM Guest Harness

Defines the **UTM macOS VM verification lane** for lyra. Use this when a
test requires OS-level side effects — service lifecycle, launchd KeepAlive,
guest reboot, unified log — without disrupting the developer's own machine.

The harness script is `.claude/scripts/lyra-vm-harness.sh`. It is
self-contained; no user-global skill or rule is required to run it.

---

## Verification lane map

| Scenario | Lane |
|---|---|
| Service install / uninstall / KeepAlive resurrection | VM (`lyra-vm-harness.sh`) |
| Daemon crash recovery | VM |
| Guest OS reboot persistence | VM |
| Unified log / OSLog observation | VM |
| CPU / memory profiling (`lyra benchmark`, `sample`) | VM |
| Screen resolution change (approximation via Dynamic Resolution) | VM — see note below |
| `lyra healthcheck` / API smoke | VM |
| Display hot-plug (external monitor attach / detach) | ScreenProvider fixture + final manual smoke |
| NSScreen topology change (`NSApplicationDidChangeScreenParameters`) | ScreenProvider fixture |
| Visual overlay pixel verification | Host debug-build lane (`dev-verification.md`) |

### Dynamic Resolution — approximation, not hot-plug

UTM Dynamic Resolution changes the guest framebuffer resolution when the UTM
window is resized. It does **not** add or remove `NSScreen` entries; the
screen count stays at 1. It is useful for verifying that `AppWindow.apply`
reconciles a frame change (#265 regression class), but it is NOT a substitute
for testing display topology changes.

**Do not describe a Dynamic Resolution test as verifying "monitor hot-plug".**

### Display topology → ScreenProvider fixture

`NSScreen` count changes cannot be automated inside a VM. Inject a fixture
`ScreenProvider` in a unit or integration test instead:

```swift
// Example: exercise ScreenInteractorImpl with two screens
let fakeProvider = FakeScreenProvider(screens: [primaryScreen, secondScreen])
let interactor = withDependencies {
    $0.screenProvider = fakeProvider
} operation: {
    ScreenInteractorImpl()
}
```

Reserve physical hot-plug confirmation for the final manual smoke check — one
confirmation per PR that modifies `ScreenInteractor` or `AppWindow`.

---

## Prerequisites

1. UTM installed: `brew install --cask utm`
2. A registered UTM macOS Apple-backend VM (macOS 15+)
3. Guest has: Xcode CLT, Homebrew, lyra installed via brew (formula must be
   known so `brew services` can manage it), and passwordless sudo
4. SSH key at `~/.ssh/lyra_vm_rsa` (default); configure via
   `LYRA_VM_SSH_KEY` env var if different

One-time guest setup:

```sh
xcode-select --install
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install lyra
brew services stop lyra   # harness will manage the service
# Add to /etc/sudoers: admin ALL=(ALL) NOPASSWD: ALL
```

---

## Harness script

```sh
SCRIPT=".claude/scripts/lyra-vm-harness.sh"
VM="lyra-test"   # exact name shown in utmctl list

$SCRIPT boot     $VM          # start + wait for SSH
$SCRIPT run-lyra $VM          # build on host, push, install, start daemon
$SCRIPT exec     $VM -- lyra healthcheck
$SCRIPT exec     $VM -- lyra track
$SCRIPT capture  $VM /tmp/out # screenshot + unified log + process sample
$SCRIPT restore  $VM          # kill daemon, restore brew service state
$SCRIPT shutdown $VM          # graceful guest shutdown
```

### Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `LYRA_VM_SSH_USER` | `admin` | Guest login name |
| `LYRA_VM_SSH_KEY` | `~/.ssh/lyra_vm_rsa` | SSH private key path |
| `LYRA_VM_SSH_PORT` | `22` | Guest SSH port |
| `LYRA_VM_BOOT_TIMEOUT` | `120` | Seconds to wait for SSH after start |
| `LYRA_VM_ARTIFACTS_DIR` | `/tmp/lyra-vm-artifacts-<ts>` | Artifact output dir |

### Always clean up

Wrap sessions in a trap so the guest is never left in a dirty state:

```sh
trap "$SCRIPT restore $VM; $SCRIPT shutdown $VM" EXIT
```

---

## Common scenarios

### Service lifecycle / KeepAlive

```sh
$SCRIPT boot $VM
$SCRIPT exec $VM -- brew services start lyra
$SCRIPT exec $VM -- "pgrep -x lyra | xargs kill -9"
sleep 5
$SCRIPT exec $VM -- pgrep -x lyra   # new PID expected
$SCRIPT capture $VM /tmp/keepalive-test
$SCRIPT exec $VM -- brew services stop lyra
$SCRIPT shutdown $VM
```

### Reboot persistence

```sh
$SCRIPT boot $VM
$SCRIPT exec $VM -- brew services start lyra
$SCRIPT reboot $VM
$SCRIPT exec $VM -- "brew services list | grep lyra"   # should show 'started'
$SCRIPT capture $VM /tmp/reboot-test
$SCRIPT exec $VM -- brew services stop lyra
$SCRIPT shutdown $VM
```

### Build + benchmark in VM

```sh
$SCRIPT boot $VM
$SCRIPT run-lyra $VM
$SCRIPT exec $VM -- "lyra benchmark -d 30 --json" > /tmp/vm-benchmark.json
$SCRIPT restore $VM
$SCRIPT shutdown $VM
```

---

## Agent rules

- **Use `lyra-vm-harness.sh` for all guest operations.** Do not craft raw
  `ssh`/`utmctl` commands from scratch — the script handles key options,
  state persistence, and restore consistently.
- **Never describe Dynamic Resolution as hot-plug.** These are distinct
  scenarios. Use the correct label in test names, issue descriptions, and
  commit messages.
- **ScreenProvider fixture owns topology tests.** Any code path depending on
  `NSScreen` count changing must have a fixture-based test. The VM does not
  replace this requirement.
- **Restore always runs.** The `restore` subcommand must run even if an
  intermediate step fails. Use `trap` in any script that calls `run-lyra`.
