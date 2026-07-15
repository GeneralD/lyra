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
  Lyrics are cached (and read back) under the matched candidate's
  title/artist rather than `candidates.first`, and both the GUI
  (`TrackInteractorImpl`) and CLI (`TrackHandlerImpl.infoWithLyrics`) fall
  back to the raw title/artist -- never an unvalidated candidate guess --
  when nothing validates. See `docs/ARCHITECTURE.md` (Key Design Decisions,
  #308) for full detail.
- Config hot-reloads without a daemon restart. `ConfigUseCase.reload()` keeps
  the previous `AppStyle` in effect on any failure (unreadable file, decode
  error, or a file that resolves to defaults while it still exists) --
  never regress on a bad edit. The new `ConfigWatchGateway` (Domain) /
  `FileWatchGateway` (Support) pair watches the config's *parent directory*
  (atomic saves rename the file) via `DispatchSource`, and the new
  `ConfigInteractor` module debounces watch events before calling
  `reload()` and republishing the outcome over Combine. An invalid reload
  is shown graphically (an amber "destabilized" geodesic sphere via
  `ConfigStatusPresenter`/`ConfigStatusOverlay`) since a daemon has no
  visible stderr. See `.claude/CLAUDE.md` (Key Design Decisions, #41) for
  full detail. PR1 ships the pipeline + the lyrics `fallback_command`
  hot-reload only; wiring feature Presenters to re-render on config change
  is follow-up work.

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
  `DependencyInjection`, `docs/ARCHITECTURE.md`, `.claude/CLAUDE.md`, this
  `AGENTS.md`, and `README.md`.
- Handler additions also need Entity result types, Domain protocols,
  `StandardOutput` support, CLI wiring, and tests.
- Do not commit directly to `main`. Use branch -> PR -> merge.
- Every PR should include a version bump in
  `Sources/VersionHandler/Resources/version.txt`.
