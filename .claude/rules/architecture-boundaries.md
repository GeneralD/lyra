# Architecture Boundaries

## Layer Responsibilities

| Layer | Owns | Never |
|---|---|---|
| **Entity** | Pure data types, enums, Codable structs | Logic, imports beyond Foundation |
| **Domain** | Protocols, DependencyKeys | Data type definitions, Foundation import |
| **Handler** | Business/measurement logic, orchestration | Output formatting, UI concerns |
| **StandardOutput** | Formatting, terminal control (echo, `\r`) | Business logic, handler references |
| **CLI Command** | Argument parsing, thin glue | Loops, task groups, complex branching |

## CLI Command Pattern

All commands follow: **inject → call → write → guard**. No exceptions.

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

- **No Foundation import** — use `Double` not `TimeInterval`, `String` not `URL`
- **Only protocols + DependencyKey** — data types go in Entity
- **No logic** — Domain is a contract layer, not an implementation layer

## Handler ↔ Output Separation

- Handlers return data (values, streams). They never format or print.
- Output receives data and formats it. It never calls handlers or orchestrates work.
- **Never pass a handler as an argument to an output method.** If output needs data during display (e.g., live metrics), the handler should stream it.

## Testing Constraints

- **Never use `setenv`** — process-global, races with Swift Testing parallel execution. Inject values via constructor parameters instead.
