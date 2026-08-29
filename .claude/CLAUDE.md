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

**Async test timing**: Never use fixed `Task.sleep` to wait for state changes in Presenter/Interactor tests. CI environments have variable load, and fixed delays cause flaky failures. Pick the wait by *what* you are waiting on:

- **State the subject publishes** — a presenter's `@Published` property, a spy that publishes what it recorded — is waited on by awaiting the publisher: `settle(_:until:)` (`Tests/TestSupport/Settle.swift` in the shared `TestSupport` target — #347, #349) suspends until the publisher emits a value that satisfies the condition. The wait is on the event itself, so it assumes nothing about time or executor ordering, and a value already published satisfies it at once; give the suite `.timeLimit` so a regression is reported instead of hanging. A deadline poll is **not** deterministic here: the work it watches is a chain of main-queue hops (a `@MainActor` `Task`, an `AsyncStream` consumed there, a `.receive(on: DispatchQueue.main)` hop), and when CI stalls the main queue the poll's expired continuation runs *before* the `.receive(on:)` block queued behind it and asserts on state that lands a moment later. Do **not** reach for `withMainSerialExecutor` / `uncheckedUseMainSerialExecutor` either: the hook is process-wide, and under Swift Testing's parallel run it stalled tests in six unrelated targets (#347).
- **State a spy you own records off the main actor** — a Combine sink on the interactor's worker, a nonisolated `Task`, a gateway callback — is recorded into `Collector<Element>` (`Tests/TestSupport/Collector.swift` — #349) and awaited with `waitForCount(_:)` / `waitFor(predicate:)` / `settle(until:)`: `append(_:)` resumes the waiter the moment the condition holds, with no deadline and no `@MainActor` requirement, so the `NSLock`-plus-`waitForCount(_:timeout:)` collectors it replaced are gone.
- **State the test itself drives** — a presenter whose display link the test stands in for (`updateActiveLineTick()`, `tick()`) — is advanced with `tickUntil(_:tick:until:)` (`Tests/TestSupport/TickUntil.swift` — #349): the bound is a tick *budget*, not a wall clock, because the writer of the awaited value is the test, so awaiting the publisher without ticking would hang. Assert the returned `Bool`; `tickUntil(n, …) == false` is also how "nothing happens after n ticks" is proved. Cancellation yields `false` too, but never a false pass: the only thing that cancels a test task is its `.timeLimit`, which has already recorded the failure.
- **State that is only readable** — a file a subprocess writes, `kill(pid, 0)`, a child the OS has yet to reap — has no in-process writer and no callback, so nothing can be awaited. Poll it with `pollUntil(timeout:interval:_:)` (`Tests/TestSupport/PollUntil.swift` — #349) and assert the result (`try #require(await pollUntil { … })`); the timeout is a guardrail on the failing path, never a delay on the passing one. A `DispatchSource` or FSEvents delivery is **not** this case: the gateway's callback is a spy you own, so record it into a `Collector` — only the OS's *cause* is external, the signal is in-process. The same goes for a child process's exit: never call `Process.waitUntilExit()` after an `await` — it runs the *calling* thread's run loop while Foundation delivers the exit to the thread that launched the process, so a test resumed on another cooperative thread hangs in the join (`DarwinGatewayTests/LaunchedProcess.swift` records the termination handler into a `Collector` and awaits that instead — #349).
- **Proving that something does *not* happen** (a duplicate emission does not re-trigger, `stop()` releases the subscription) cannot be a wait on a value. Either wait for the mechanism that guarantees the absence — a `handleEvents(receiveCancel:)` spy on the publisher the presenter subscribes to, recorded into a `Collector<Void>` and awaited after `stop()`, after which a `send` reaches nobody and the plain `#expect` is sound — or send a **sentinel** through the same pipeline (a distinct update that must take effect), `settle` on a value only the sentinel can produce (a distinct title, a distinct artwork *size* — not the image's identity, which a duplicate re-decode changes just as well), and assert that the transitions recorded in between contain no re-trigger; in-order delivery on one pipeline is what makes the sentinel a proof. A fixed sleep or a short-deadline poll proves nothing here, and passes vacuously on a stalled runner.

```swift
// Good — await the value's own publisher
await settle(presenter.$titleState) { $0.isSuccess }

// Good — readable-only state, bounded poll whose expiry is reported where it happened
try #require(await pollUntil { FileManager.default.fileExists(atPath: pidFile) })

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
