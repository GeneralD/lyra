# AGENTS.md

This file is the Codex entrypoint for `lyra`.

The long-form architecture and workflow docs still live under `.claude/`. Keep
this file concise, and open the referenced files before making the
corresponding kinds of changes.

## Read Before Changing

- Architecture, dependency graphs, and module responsibilities:
  `docs/ARCHITECTURE.md` (canonical; `.claude/CLAUDE.md` keeps a short
  summary + pointer)
- Guardrails for layering, CLI boundaries, and test constraints:
  `.claude/rules/architecture-boundaries.md`
- Module addition and documentation sync checklist:
  `.claude/rules/module-checklist.md`
- Swift implementation style and immutability rules:
  `.claude/rules/swift-idioms.md`
- Running the debug build for visual verification while the brew service is
  installed (stop -> run -> restore): `.claude/rules/dev-verification.md`
- Repo-local version bump workflow:
  `.codex/skills/lyra-bump-version/SKILL.md`

## Build And Verify

```sh
swift build
swift build -c release
swift test
swift test --filter ConfigTests
make build
make install
make lint
make format
make benchmark
lyra benchmark
lyra benchmark -d 30 --json
swift .claude/scripts/check-overlay.swift
```

## Project Summary

`lyra` is a macOS desktop lyrics overlay and video wallpaper app.

Core dependency direction:

```text
CLI/App -> AppRouter/Views/Presenters -> Interactors -> UseCases
         -> Repositories -> DataSources/DataStores
```

Shared conventions:

- `Entity` owns pure data types.
- `Domain` owns protocols and `DependencyKey` definitions for
  cross-layer contracts. The one exception is the `App`-module
  AppKit foreground lifecycle key (`ForegroundApplicationRunnerKey`),
  which lives in `App` because its live implementation owns
  `NSApplication` and `AppDelegate` setup.
- `DependencyInjection` owns Domain-facing live registrations. The
  App-module bootstrap key is the lone non-Domain registration site.
- `App` owns AppKit foreground lifecycle and termination-signal seams.
- `Presenters` own display state.
- `Views` stay declarative and rendering-focused.
- `StandardOutput` owns terminal formatting.
- `Package.swift` exposes a `LyraKit` library product beside the `lyra`
  executable, so sibling repos — e.g. the planned `lyra-screensaver` `.saver`
  (#325) — can reuse the video-wallpaper pipeline over SPM. The product is a
  single `LyraKit` umbrella target (a `@_exported import` facade over
  `Entity` / `Domain` / `Presenters` / `DependencyInjection`), so a consumer
  writes one `import LyraKit`. It is an internal-reuse surface, not a
  stability-guaranteed public API.

## Non-Negotiable Rules

- CLI commands follow `inject -> call -> write -> guard`. Commands are thin glue
  only; do not put loops, task groups, or orchestration logic in command types.
- Keep `RootCommand` sync. Async subcommands should continue to use
  `AsyncRunnableCommand`; do not switch the app entry to `AsyncParsableCommand`.
- `Domain` must not import `Foundation`. Use plain Swift types in protocol
  signatures, and put concrete data types in `Entity`. Framework imports are
  allowed only as boundary-shaped exceptions recorded in CLAUDE.md Key Design
  Decisions (currently Combine for Interactor streams and CoreAudio for
  `AudioTapGateway`, #313).
- Handlers, use cases, and repositories return data. `StandardOutput` formats
  and prints it. Never pass handler instances into output methods.
- Views do not own business logic. Keep orchestration in Presenters and
  Interactors. The existing rendering-only dependency access patterns may stay,
  but do not add feature logic to SwiftUI views.
- Prefer `let` and functional transforms. Every `var` should have a real reason
  to exist.
- Repositories own cache strategy. DataSources stay focused on API, file, and
  OS integration work.
- Metadata and lyrics resolution never short-circuit on first success: all
  metadata sources (LLM/MusicBrainz/Regex) are queried and merged, and every
  lyrics tier (LRCLIB exact match, validated fuzzy search, user
  `fallback_command` script) is tried across all candidates before giving up.
  An opt-in `[developer] lyrics_resolution` trace (#331) records each tier's
  accept/reject with its reason (title similarity, duration delta) to a local
  file for diagnosing intermittent misses; it is off by default and
  behavior-neutral.
  Lyrics are cached (and read back) under the matched candidate's
  title/artist rather than `candidates.first`, and both the GUI
  (`TrackInteractorImpl`) and CLI (`TrackHandlerImpl.infoWithLyrics`) fall
  back to the raw title/artist -- never an unvalidated candidate guess --
  when nothing validates. See `docs/ARCHITECTURE.md` (Key Design Decisions,
  #308) for full detail.
- Config hot-reloads without a daemon restart. `ConfigUseCase.reload()` keeps
  the previous `AppStyle` in effect when the **required** structure fails to
  validate (unreadable file, decode error in a core section, or a file that
  resolves to defaults while it still exists) -- never regress on a bad edit.
  A malformed **optional** `[ai]`/`[lyrics]` section instead degrades to `nil`
  like startup and does not block a valid edit; `lyra healthcheck` still
  reports it (the strictness is the `strictOptionalSections` flag on
  `validate`/`tryDecode`, #330). The `ConfigWatchGateway` (Domain) /
  `FileWatchGateway` (Support) pair watches the config's *parent directory*
  (atomic saves rename the file) plus a re-armed file tier via
  `DispatchSource`. The gateway is consumed at the **DataSource layer**:
  `ConfigDataSourceImpl.watchChanges(onChange:)` owns target resolution
  (config file, `includes`, foreign include parents) and per-event re-arming,
  and the watch reaches the interactor only through `ConfigRepository` /
  `ConfigUseCase` pass-throughs -- adjacent layers only, no layer skipping.
  The directory watch arms whether or not the file exists yet, so a config
  created after the daemon starts (`lyra config init`, a manual save) is
  picked up as the initial load without a restart, as long as the config
  directory exists at start (#329). The
  `ConfigInteractor` module debounces watch events before calling
  `reload()` and republishing the outcome over Combine. An invalid reload
  is shown graphically (an amber "destabilized" geodesic sphere via
  `ConfigStatusPresenter`/`ConfigStatusOverlay`) since a daemon has no
  visible stderr. See `docs/ARCHITECTURE.md` (Key Design Decisions, #41) for
  full detail. Header/Lyrics styling, the ripple/spectrum overlays (styling
  plus the `enabled` toggle), the wallpaper source, and the screen selection
  now all re-render live -- each Presenter subscribes once to `appStyleChanges`
  and reflects the change in an idempotent `applyStyle()`, and the DisplayLink
  fan-out always includes the ripple/spectrum frame handlers (their enabled
  guard lives inside the handler, #41 PR3). The wallpaper reload diffs the
  source and swaps the video via `replaceCurrentItem` on the same AVPlayer, so
  the overlay never blacks out; removing all wallpaper tears the player down and
  detaches the layer, restoring the transparent backing rather than leaving a
  black surface; the screen reload re-runs `resolveLayout()` and restarts vacant
  polling on a new selector/debounce (#41 PR4). Config hot-reload now covers
  every visual element -- #41 is functionally complete.

## Testing Rules

- Do not wait on async state with fixed `Task.sleep` delays. Poll until a
  deadline instead.
- Do not use `setenv` in tests. Inject config paths or environment-derived
  values through constructors or dependencies.
- UI tests must select fixture graphs during app bootstrap in `AppDelegate`
  and/or `AppRouter`. In-memory `withDependencies` overrides do not cross the
  process boundary.
- Test display logic in Presenters and `SwiftUIResolver`; do not unit test
  SwiftUI view bodies.

## Change Checklist

- When adding or removing modules, update `Package.swift`,
  `DependencyInjection`, `docs/ARCHITECTURE.md`, this `AGENTS.md`, and
  `README.md`. Update `.claude/CLAUDE.md` only when Build & Test commands
  change or the layer chain itself changes — its architecture section is a
  short summary + pointer, and `docs/ARCHITECTURE.md` is the canonical
  reference (see `.claude/rules/module-checklist.md`).
- Handler additions also need Entity result types, Domain protocols,
  `StandardOutput` support, CLI wiring, and tests.
- Do not commit directly to `main`. Use branch -> PR -> merge.
- Every PR should include a version bump in
  `Sources/VersionHandler/Resources/version.txt`.
