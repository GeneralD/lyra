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

## File Naming — A File Is Named After Its Main Type

**Every Swift file under `Sources/` is named after the main type it declares**
(#372). A file that holds a main type plus small supporting types keeps the main
type's name. A file with no main type — a family of result/record/model types
grouped under an umbrella name, as the former `ServiceResult.swift` and
`Records.swift` were — is split **one type per file**, and each top-level
`typealias` gets its own file too (`ServiceInstallResult.swift` holds only
`typealias ServiceInstallResult = Result<…>`). A type is then found by its name
alone, with no umbrella file to remember.

Allowed exceptions, each because the file's name describes something other than
a single type:

- **`Type+Feature.swift`** (the name contains `+`) — an extension file; the
  extended type lives elsewhere.
- **`*Registration.swift`** — DI wiring; it registers live values and may hold
  private helper types (no-op stubs such as `NoopLyricsDataStore`) that exist
  only for that registration.
- **Papyrus `XxxAPI.swift`** — declares `@API protocol Xxx`, and the `@API`
  macro generates the `XxxAPI` type that callers actually use, so the file is
  named after that type. Other types (request/response models) still go in their
  own files.
- **No top-level type at all** — free functions, `@_exported` re-exports, or
  extensions only; there is no type name to match.

Enforced by `scripts/lint-file-names.swift`, which `make lint` and the CI
`lint` job run after swift-format. Files under a `Resources/` directory are
skipped: they are bundled scripts run by the interpreter at runtime (the
MediaRemote helper), not module sources.

## View File Organization — `XxxxView.swift` Holds Only the Struct

**A `XxxxView.swift` file must contain only the pure SwiftUI `View` struct.**
Everything else — bar/rect geometry, gradient math, alignment helpers, and even
`GraphicsContext` drawing — is *logic*, not view declaration, so it lives in
sibling files. The `View`'s `body` delegates to those collaborators; it never
defines them.

**Group the logic into structs, not a global-namespace free-function bag.**
Swift is OO at its core (see `code-philosophy` / `swift-conventions` — free
functions are the FP default for a *loose* collection of helpers; a *cohesive*
unit is an instantiated struct). Spectrum geometry and drawing are cohesive, so
each is a `struct` the View holds as an instance. This scopes the API out of the
global namespace and makes each collaborator DI-able.

Two structs, split by testability so the coverage boundary is a *file* boundary:

- `XxxxGeometry.swift` — a plain `struct` of pure methods (`size`/`style` →
  rects, points, alignment, `Path`). Unit-tested against an instance, no live
  `GraphicsContext`.
- `XxxxRenderer.swift` — a `@MainActor struct` owning the irreducible Canvas
  drawing (`context.fill` / `drawLayer`) plus its collaborators (the
  `@Dependency`-injected resolver, a geometry instance). Cannot run without a
  real context, so it stays untested *by design* — but it is *thin*, since every
  value it draws came from the tested geometry.

```swift
// SpectrumView.swift — struct only; holds instances, body delegates
@ObservedObject var presenter: SpectrumPresenter
private let geometry = SpectrumGeometry()
private let renderer = SpectrumRenderer()

public var body: some View {
    Canvas { context, size in
        renderer.draw(&context, size: size, heights: presenter.binHeights(), style: style)
    }
    .frame(height: geometry.stripDepth(in: proxy.size, style: style))
}

// SpectrumGeometry.swift — pure struct, tested (type name drops the prefix)
struct SpectrumGeometry {
    func barRects(in size: CGSize, heights: [Float], …) -> [SpectrumBar] { … }
    func stripDepth(in available: CGSize, style: SpectrumStyle) -> CGFloat { … }
}

// SpectrumRenderer.swift — @MainActor struct, GraphicsContext plumbing, thin
@MainActor
struct SpectrumRenderer {
    @Dependency(\.swiftUIResolver) private var resolver
    private let geometry = SpectrumGeometry()
    func draw(_ context: inout GraphicsContext, …) { … }
}
```

Why: a `View` file that also holds computation drags untestable declaration
around testable logic. Moving it into a struct makes it instance-testable
(pushed by the "Untestable = insufficient abstraction" principle) *and* keeps
the OO grouping instead of littering the global namespace; the View struct then
reads as a one-glance description of what renders.

**This is View-layer logic, not Presenter logic.** The Presenter already owns
the *presentation* decisions (here: the 0…1 bar levels via cava physics, fully
tested as `binHeights()`); geometry/renderer only *map those decided values onto
pixels* and speak SwiftUI/CoreGraphics (`CGRect`/`Path`/`Alignment`/
`GraphicsContext`). Hoisting them into the Presenter would force SwiftUI imports
and the per-frame canvas size into it — a layer inversion. Keep the seam at
"Presenter decides values → View maps values to pixels."

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
