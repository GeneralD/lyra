# Dev Verification — Run the Debug Build, Not the Installed One

When you need the user to **visually verify lyra runtime behavior** (overlay
rendering, ripple, lyrics, wallpaper — anything that requires the daemon to
actually run and draw on screen), you must make the debug build the *only*
running instance. On a machine where the Homebrew service is installed, that
means taking the brew service offline first, running the debug build in the
foreground, letting the user confirm, then **restoring the service to its
prior state**.

This is a standing behavioral mandate. **Whenever runtime verification is
wanted — whether you propose it OR the user says they want to check something
(e.g. "I want to see how this looks", "動作確認したい") — drive this
stop → run → restore cycle yourself.** Stop the running (brew) instance, show
the debug build, then put the service back. Do not tell the user to wrestle
with the lock race or the service lifecycle by hand.

## Why the installed service gets in the way

- The brew service (`homebrew.mxcl.lyra`) runs under launchd with
  `KeepAlive = true`. `lyra stop` (pgrep + `SIGTERM`/`SIGKILL`) cannot keep it
  down — launchd resurrects the brew binary the instant it dies, and the
  resurrected process re-grabs the single-instance flock at
  `~/.cache/lyra/lyra.pid`. The debug `lyra daemon` then loses the race and
  never starts.
- If both instances *do* run (e.g. with separate lock dirs), **both draw the
  overlay**. Z-order becomes ambiguous — you cannot tell which build you are
  looking at — and `check-overlay.swift` (matches `kCGWindowOwnerName == "lyra"`)
  reports multiple windows. Verification becomes meaningless. Exclusivity is
  required, not coexistence.
- Only `brew services stop lyra` (which boots the launchd job out, like
  `launchctl bootout gui/$UID/homebrew.mxcl.lyra`) keeps it down. General
  principle: **a KeepAlive launchd job must be booted out, not just killed.**

## Procedure

```sh
# 1. Capture prior state — is the brew service running?
brew services list | grep '^lyra'        # note "started" vs "stopped"/"none"

# 2. If it was started, take it offline so KeepAlive cannot resurrect it.
brew services stop lyra

# 3. Build and run the debug build in the FOREGROUND.
swift build && .build/debug/lyra daemon
#   - `daemon` runs the accessory in the foreground: logs are visible and
#     Ctrl-C stops it. `start` spawns a detached daemon and nulls stdout — not
#     for dev verification.

# 4. Let the user verify visually. Optionally assert the overlay is live
#    (now unambiguous — only the debug instance is running):
swift .claude/scripts/check-overlay.swift

# 5. Ctrl-C to stop the debug daemon.

# 6. ALWAYS restore prior state.
brew services start lyra                  # only if step 1 showed "started"
```

## Guardrails

- **Always restore.** Never leave the machine with the brew service stopped.
  Run the restore step even if the build or run failed partway.
- **Restore to prior state, don't impose a new one.** Only `brew services
  start lyra` if step 1 showed it was `started`. If the user had it off, leave
  it off.
- **Keep the build portable — never bake brew into the Makefile.** This is an
  agent operational responsibility, not a build target. `swift build` / `make`
  must stay brew-agnostic so CI, Linux, non-brew, and `lyra start` users are
  unaffected.
- **Manual (`lyra start`) installs need no brew commands.** A daemon started
  by `lyra start` (no KeepAlive) is stopped sufficiently by `lyra stop`;
  restart with `lyra start`. Detect which flavor is running before acting.
- **The debug binary is a different path** (`.build/debug/lyra`) than the brew
  binary. It shares the real config and `~/.cache/lyra` (intended — you are
  verifying real behavior), but TCC-gated capabilities granted to the brew
  binary may need granting to the debug path too if a feature depends on them.
