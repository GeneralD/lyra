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

## View File Organization — `XxxxView.swift` Holds Only the Struct

**A `XxxxView.swift` file must contain only the pure SwiftUI `View` struct.**
Everything else — bar/rect geometry, gradient math, alignment helpers, and even
`GraphicsContext` drawing — is *logic*, not view declaration, so it lives in
sibling files. The `View` struct's `body` calls out to those free functions; it
never defines them or the drawing methods.

Two logic files split by testability so the coverage boundary is a *file*
boundary:

- `XxxxGeometry.swift` — pure functions (`size`/`style` → rects, points,
  alignment, `Path`). Unit-tested directly, no live `GraphicsContext`.
- `XxxxRendering.swift` — the irreducible Canvas drawing (`context.fill` /
  `drawLayer`). Cannot run without a real context, so it stays untested by
  design — but it is *thin*, since every value it draws came from the tested
  geometry.

```swift
// SpectrumView.swift — struct only; body delegates
public var body: some View {
    Canvas { context, size in
        drawSpectrumBars(&context, size: size, heights: presenter.binHeights(), style: style)
    }
    .frame(height: barStripDepth(in: proxy.size, style: style))   // geometry fn
}

// SpectrumGeometry.swift — pure, tested
func spectrumBarRects(in size: CGSize, heights: [Float], …) -> [SpectrumBar] { … }
func barStripDepth(in available: CGSize, style: SpectrumStyle) -> CGFloat { … }

// SpectrumRendering.swift — GraphicsContext plumbing, untestable but thin
@MainActor func drawSpectrumBars(_ context: inout GraphicsContext, …) { … }
```

Why: a `View` file that also holds computation drags untestable declaration
around testable logic. Moving the logic out makes it free-function-testable
(pushed by the "Untestable = insufficient abstraction" principle), and the
struct reads as a one-glance description of what renders.

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
