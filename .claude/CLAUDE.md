# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Keep the repository root `AGENTS.md` in sync when build/test commands,
architecture boundaries, or workflow rules change. Codex uses `AGENTS.md` as
its project entrypoint, while this file holds the long-form conventions and
workflow reference. The architecture design — module dependency graphs, layer
tables, and Key Design Decisions — lives in `docs/ARCHITECTURE.md`; keep it in
sync when modules or architecture change.

## Build & Test

```sh
swift build                          # debug build
swift build -c release               # release build
swift test                           # run all tests
swift test --filter ConfigTests      # run single test suite
make build                           # release build via Makefile
make install                         # install to /usr/local/bin
make lint                            # check formatting (swift-format)
make format                          # auto-fix formatting
make benchmark                       # run CPU/memory benchmarks (release build)
lyra benchmark                       # measure baselines (idle, cpu_spike, memory_alloc)
lyra benchmark -d 30 --json          # 30s per scenario, JSON output
swift .claude/scripts/check-overlay.swift  # verify overlay is rendering
```

To run the debug build for visual verification while the Homebrew service is
installed, follow `.claude/rules/dev-verification.md` (stop the brew service ->
run `.build/debug/lyra daemon` in the foreground -> restore the service).

## Architecture

macOS desktop overlay app showing synced lyrics and video wallpaper. VIPER + Clean Architecture with Swift Package targets enforcing layer boundaries at compile time.

```text
View → Presenter → Interactor → UseCase → Repository → DataSource
                 → Router (wireframe only)
```

Presenters subscribe to Interactors via Combine. Interactors access UseCases via `@Dependency`. Views never reference Interactors or UseCases directly.

> **Full architecture reference → [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md).**
> The module dependency graphs (Layer Overview + Implementation Modules), the
> VIPER component summary, the layer/module table, and the per-issue **Key
> Design Decisions** rationale live there — read it before making architectural
> changes. The **enforceable** layer boundaries are in
> `.claude/rules/architecture-boundaries.md`.

### Testing Guidelines

**Async test timing**: Never use fixed `Task.sleep` to wait for state changes in Presenter/Interactor tests. CI environments have variable load, and fixed delays cause flaky failures. Always use polling helpers:

```swift
// Good — poll until condition is met
let deadline = ContinuousClock.now + .seconds(3)
while !presenter.titleState.isSuccess, ContinuousClock.now < deadline {
    try? await Task.sleep(for: .milliseconds(10))
}

// Bad — fixed delay that may be too short on CI
try? await Task.sleep(for: .milliseconds(200))
#expect(presenter.titleState == .success("Song"))
```

This applies to all Combine + Timer + MainActor tests where DecodeEffect, state transitions, or async operations are involved.

**Never use `setenv` in tests.** `setenv` is process-global and Swift Testing runs suites in parallel — concurrent tests clobber each other's environment variables, causing flaky CI failures. Instead, add a constructor parameter (e.g., `ConfigDataSourceImpl(configHome:)`) and inject the value directly.

**Domain module has no Foundation import.** Use `Double` instead of `TimeInterval`, `String` instead of `URL`, etc. in Domain protocol signatures.

**View testing strategy**: SwiftUI Views (body) are not unit-tested. All display logic is pushed to Presenters, which are thoroughly tested. Views are pure rendering with no business logic.

**SwiftUIResolver**: Config→SwiftUI type conversions (font, color, shapeStyle, lineHeight) are centralized in `SwiftUIResolver` protocol with DI. Views access via `@Dependency(\.swiftUIResolver)` in body. `LiveSwiftUIResolver` is tested directly in `SwiftUIResolverTests`.

### Git Workflow

**Never commit directly to main.** All changes, including documentation-only updates, must go through a branch → PR → merge flow. Documentation-only changes (CLAUDE.md, README, etc.) should normally be batched into the next code-change PR, but small doc-only PRs are acceptable when needed; direct commits to `main` are never allowed.

### Version Management

Version is defined in `Sources/VersionHandler/Resources/version.txt` (single source of truth). CI reads this file to auto-create/update git tags on push to main.

**PR version bump rule**: When creating a PR, always include a version bump commit. Determine the level from the changes in the PR:

- `feat:` → minor bump
- `fix:` / `refactor:` / `chore:` → patch bump
- Breaking changes → major bump
