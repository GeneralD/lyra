# Architecture Boundaries

## Layer Responsibilities

| Layer | Owns | Never |
|---|---|---|
| **Entity** | Pure data types, enums, Codable structs | Logic, imports beyond Foundation |
| **Domain** | Protocols, DependencyKeys | Data type definitions; framework imports beyond the documented boundary-shaped exceptions (Combine in Interactor protocols, CoreAudio in `AudioTapGateway` — see docs/ARCHITECTURE.md Key Design Decisions, #313) |
| **Handler** | Business/measurement logic, orchestration | Output formatting, UI concerns |
| **StandardOutput** | Formatting, terminal control (echo, `\r`) | Business logic, handler references |
| **CLI Command** | Argument parsing, thin glue | Loops, task groups, complex branching |
| **DataStore** | Persistence/cache of *domain data* — Entity values a Repository reads back (SQLite caches, wallpaper files) | Caching *computational resources* (memoized engines, FFT setups, formatters) — those stay private state of the owning implementation (see docs/ARCHITECTURE.md "Analyzer memoization", #313) |

## Dependency Chain — Adjacent Layers Only, No Skipping

Within the VIPER lane, each layer depends only on the layer directly beneath it:

```text
View → Presenter → Interactor → UseCase → Repository → DataSource/DataStore → Gateway (OS boundary)
```

- **No layer skipping.** An upper layer must not consume a lower-lower layer
  directly, even when `@Dependency` makes it a one-liner — an Interactor
  holding a Gateway is a violation regardless of how convenient the DI graph
  makes it (#337: `ConfigInteractor` → `ConfigWatchGateway` was refactored
  into the adjacent chain).
- **OS-boundary gateways are consumed at the DataSource layer.** Precedents:
  `AudioTapDataSource → AudioTapGateway`, `ConfigDataSource →
  ConfigWatchGateway`. When an upper layer needs OS-boundary behavior, thread
  a contract through the adjacent layers as pass-throughs (e.g.
  `watchChanges(onChange:)` on UseCase → Repository → DataSource) instead of
  reaching down.
- **Knowledge placement follows the chain too.** Path resolution, normalization,
  and other persistence-shaped knowledge live in the DataSource; the layers
  above see only the contract.

## CLI Command Pattern

All commands follow: **inject → call → write → guard**. No exceptions.

Commands contain zero logic — no loops, task groups, branching, or data
transformation. This ensures:

- **Testability**: handler and output are independently testable without CLI
- **Readability**: each command reads as a one-line description of what it does
- **Separation of concerns**: handler owns logic, output owns formatting, command is glue only

```swift
func run() async throws {
    @Dependency(\.handler) var handler
    @Dependency(\.standardOutput) var output
    let result = await handler.doWork(...)
    output.write(result)
    guard case .success = result else { throw ExitCode.failure }
}
```

If a command needs streaming output, iterate the stream and call output methods — but never put orchestration logic (task groups, concurrent sampling, timers) in the command.

## Domain Module Constraints

- **No Foundation import by default** — use `Double` not `TimeInterval`, `String` not `URL`
- **Framework imports only as documented boundary-shaped exceptions** — when
  the boundary's shape IS the contract and plain-type wrapping would cost
  correctness or performance, a framework import is allowed but must be
  recorded in docs/ARCHITECTURE.md Key Design Decisions. Current exceptions: Combine
  (Interactor protocols expose reactive streams), CoreAudio
  (`AudioTapGateway` — type-erasing `CATapDescription`/`AudioDeviceIOBlock`
  would force allocation on the RT-safe IOProc path, #313)
- **Only protocols + DependencyKey** — data types go in Entity
- **No logic** — Domain is a contract layer, not an implementation layer

## Handler ↔ Output Separation

- Handlers return data (values, streams). They never format or print.
- Output receives data and formats it. It never calls handlers or orchestrates work.
- **Never pass a handler as an argument to an output method.** If output needs data during display (e.g., live metrics), the handler should stream it.

## Protocol API Design

- **Don't expose implementation details in protocols.** If only one implementation
  needs a method (e.g., `suppressEcho`), keep it `private` in that implementation.
  Protocols define the contract consumers need, not the mechanics of one backend.
- **Event enums should be self-contained.** Each case handles its own lifecycle
  (e.g., `.live` suppresses echo, `.completed` restores it). Don't add separate
  setup/teardown events (`.started`, `.finished`) when cases can manage their own state.
- **AsyncStream ending is the natural cleanup signal.** When `for await` exits,
  the work is done. Don't yield a redundant `.finished` event — it duplicates
  what the stream already communicates.

## Testing Constraints

- **Never use `setenv`** — process-global, races with Swift Testing parallel execution. Inject values via constructor parameters instead.
- **UI tests require bootstrap, not in-memory overrides.** `XCUIApplication` launches the app in a separate process, so unit-test-style `withDependencies` overrides do not cross the process boundary. Select any fixture graph at app startup (launch arguments/environment in `AppDelegate`/`AppRouter`), and keep UI-test branching out of presenters and views.
