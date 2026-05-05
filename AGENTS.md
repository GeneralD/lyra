# AGENTS.md

This file is the Codex entrypoint for `lyra`.

The long-form architecture and workflow docs still live under `.claude/`. Keep
this file concise, and open the referenced files before making the
corresponding kinds of changes.

## Read Before Changing

- Architecture, dependency direction, and module responsibilities:
  `.claude/CLAUDE.md`
- Guardrails for layering, CLI boundaries, and test constraints:
  `.claude/rules/architecture-boundaries.md`
- Module addition and documentation sync checklist:
  `.claude/rules/module-checklist.md`
- Swift implementation style and immutability rules:
  `.claude/rules/swift-idioms.md`
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
- `Domain` owns protocols and `DependencyKey` definitions only.
- `DependencyInjection` owns Domain-facing live registrations.
- `App` owns AppKit foreground lifecycle and termination-signal seams.
- `Presenters` own display state.
- `Views` stay declarative and rendering-focused.
- `StandardOutput` owns terminal formatting.

## Non-Negotiable Rules

- CLI commands follow `inject -> call -> write -> guard`. Commands are thin glue
  only; do not put loops, task groups, or orchestration logic in command types.
- Keep `RootCommand` sync. Async subcommands should continue to use
  `AsyncRunnableCommand`; do not switch the app entry to `AsyncParsableCommand`.
- `Domain` must not import `Foundation`. Use plain Swift types in protocol
  signatures, and put concrete data types in `Entity`.
- Handlers, use cases, and repositories return data. `StandardOutput` formats
  and prints it. Never pass handler instances into output methods.
- Views do not own business logic. Keep orchestration in Presenters and
  Interactors. The existing rendering-only dependency access patterns may stay,
  but do not add feature logic to SwiftUI views.
- Prefer `let` and functional transforms. Every `var` should have a real reason
  to exist.
- Repositories own cache strategy. DataSources stay focused on API, file, and
  OS integration work.

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
  `DependencyInjection`, `.claude/CLAUDE.md`, this `AGENTS.md`, and `README.md`.
- Handler additions also need Entity result types, Domain protocols,
  `StandardOutput` support, CLI wiring, and tests.
- Do not commit directly to `main`. Use branch -> PR -> merge.
- Every PR should include a version bump in
  `Sources/VersionHandler/Resources/version.txt`.
