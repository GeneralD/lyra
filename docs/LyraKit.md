<p align="center">
  <img src="../assets/lyrakit-icon-transparent.png" alt="LyraKit" width="200">
</p>

# LyraKit — Reuse lyra as a Swift library

`lyra` ships a **`LyraKit`** library product alongside the `lyra` executable so
sibling apps can reuse lyra's building blocks over SwiftPM instead of
re-implementing them. It exists for the planned **`lyra-screensaver`** `.saver`
bundle ([#325]), which drives the same video-wallpaper pipeline the daemon uses
— reading the user's existing `~/.config/lyra/config.toml` `[wallpaper]` set and
`~/.cache/lyra/wallpapers/` cache — but any Swift target on macOS 14+ can depend
on it.

> **Stability:** `LyraKit` is an _internal-reuse_ surface, not a SemVer-stable
> public API. It re-exports modules that evolve with the app; pin an exact
> version and expect to adjust on upgrades.

## Requirements

- macOS 14+
- Swift 6.0+

## Add the dependency

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/GeneralD/lyra.git", from: "2.22.0"),
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "LyraKit", package: "lyra"),
        ]
    ),
]
```

`LyraKit` is the _product_ name. In SwiftPM a product name is not itself an
importable module — but `LyraKit` is also an umbrella _target_ that
`@_exported import`s the reuse surface, so a single `import LyraKit` brings in
everything below.

```swift
import LyraKit
```

| Re-exported module | What you get |
|---|---|
| `Entity` | Pure data types — `ResolvedWallpaperItem`, `WallpaperState`, `WallpaperPlaybackMode`, `AppStyle`, … |
| `Domain` | `@Dependency` keys + protocols — `WallpaperInteractor`, `ConfigUseCase`, … |
| `Presenters` | Ready-made presentation engines — `WallpaperPresenter` (the `AVPlayer` loop / trim / cycle controller, NSWindow-free) |
| `DependencyInjection` | `liveValue` wiring, so `@Dependency` resolves to the real implementations without you re-registering the graph |

## Play the wallpaper pipeline (recommended)

`WallpaperPresenter` is the highest-level entry point: an `@MainActor`
`ObservableObject` that resolves the configured wallpaper set (local files,
HTTP(S), YouTube — downloaded and cached exactly as the daemon does), owns the
`AVPlayer` lifecycle (loop, per-item trim, cycle / shuffle advance), and reacts
to system sleep / wake. Construct it, call `start()`, and observe its published
`player`:

```swift
import LyraKit
import SwiftUI
import AVKit

struct WallpaperView: View {
    @StateObject private var presenter = WallpaperPresenter()

    var body: some View {
        ZStack {
            Color.black
            if let player = presenter.player {
                VideoPlayer(player: player)
                    .scaleEffect(presenter.wallpaperScale)
            }
        }
        .onAppear { presenter.start() }
        .onDisappear { presenter.stop() }
    }
}
```

The wallpaper set comes from lyra's own config file — nothing to pass in. Point
lyra's `[wallpaper]` at whatever you like and every `LyraKit` consumer picks it
up. (For a controls-free, aspect-fill surface, host an `AVPlayerLayer` instead
of `VideoPlayer` and set its `videoGravity` — `presenter.player` is the same
`AVPlayer` either way.)

## Resolve wallpapers yourself (advanced)

If you drive your own player, consume the interactor's stream directly. This
path uses the `@Dependency` property wrapper, so add
[`swift-dependencies`](https://github.com/pointfreeco/swift-dependencies) to
your target as well:

```swift
import LyraKit
import Dependencies

@Dependency(\.wallpaperInteractor) var wallpaper

for await item in wallpaper.resolvedWallpapers() {
    // item.url    — a local file path (remote / YouTube already downloaded & cached)
    // item.start  — optional trim-in  (seconds)
    // item.end    — optional trim-out (seconds)
    // item.scale  — per-item zoom (>= 1.0), e.g. to hide letterboxing
    play(item.url)
}
```

`.cycle` mode emits items in configured order; `.shuffle` emits each as it
resolves. Read `wallpaper.playbackMode` first to decide how to advance.

## What LyraKit does _not_ include

The umbrella deliberately excludes the CLI, the AppKit foreground lifecycle
(`App`), the overlay window (`Views` / `AppWindow`), and the lyrics / metadata
overlay stack — a `.saver` or embedding host supplies its own window and only
needs the wallpaper engine. If you need a lighter, wallpaper-only slice (to
avoid linking MediaRemote / Audio), see [#325]: splitting the DI registrations
per feature is a tracked follow-up.

[#325]: https://github.com/GeneralD/lyra/issues/325
