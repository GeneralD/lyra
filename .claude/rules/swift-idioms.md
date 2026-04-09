# Swift Idioms

## Type Safety over Strings

Use enums with `CaseIterable` instead of `[String]` for fixed sets of values.

```swift
// Bad — typos pass silently, filtering needed at runtime
var availableScenarios: [String] { ["idle", "cpu_spike"] }
scenarios.filter { available.contains($0) }

// Good — compiler enforces correctness
enum Scenario: String, CaseIterable, Sendable { case idle, cpuSpike = "cpu_spike" }
```

This eliminates `available` properties, manual filtering, and `default` branches in switch statements.

## Pattern Matching in Async Streams

Use `for await case` to filter stream variants directly.

```swift
// Good
for await case .completed(let entry) in stream { ... }

// Avoid when only one case matters
for await update in stream {
    switch update {
    case .completed(let entry): ...
    default: break
    }
}
```

## Prefer Declarative over Imperative

Minimize `var` accumulators. Use Swift's built-in patterns when possible.

```swift
// Good — functional collection via AsyncSequence
let entries = await stream.compactMap { ... }.reduce(into: []) { ... }

// Acceptable — var needed for async iteration
var entries: [Entry] = []
for await case .completed(let e) in stream { entries.append(e) }
```
