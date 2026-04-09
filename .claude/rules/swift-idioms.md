# Swift Idioms

## Immutability First

**Every `var` must be justified.** Default to `let` with functional chains.
This is the single most important coding principle in this project.

```swift
// Bad — mutable accumulator
var entries: [Entry] = []
for await case .completed(let e) in stream { entries.append(e) }

// Good — let + reduce
let entries = await stream.reduce(into: [Entry]()) {
    if case .completed(let e) = $1 { $0.append(e) }
}
```

When `Array.map` can't be used with `await`, use a private `asyncMap` helper
to hide the `var` from the call site.

## No Unnecessary Intermediate Steps

Don't create a stream just to collect it back into an array. If a direct
API can return the result, use it.

```swift
// Bad — stream → filter → collect, when batch result is available
let entries = await handler.run(...).reduce(into: []) { ... }

// Good — direct batch API
let entries = await handler.measure(...)
```

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
