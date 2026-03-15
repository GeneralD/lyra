# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test

```sh
swift build                          # debug build
swift build -c release               # release build
swift test                           # run all tests
swift test --filter TitleParser      # run single test suite
make build                           # release build via Makefile
make install                         # install to /usr/local/bin
```

## Architecture

macOS desktop overlay app showing synced lyrics and video wallpaper. Clean Architecture with 11 Swift Package targets enforcing layer boundaries at compile time.

### Layer Dependency Flow

```
backdrop (executable entry point)
  → BackdropCLI (ArgumentParser commands, ProcessManager, LaunchAgent)
    → BackdropApp (AppDelegate, OverlayWindow, DI wiring)
      → BackdropUI (SwiftUI views, @Observable state, ripple effects)
      → BackdropLyrics (cache→API→cache orchestration)
      → BackdropNowPlaying (MediaRemote notifications → AsyncStream)
      → BackdropConfig (TOML/JSON config loading, text style resolution)
        → BackdropDomain (models, protocols, DependencyKeys)
  BackdropMediaRemote (isolated, no domain dependency)
  BackdropPersistence (GRDB SQLite cache)
  BackdropLRCLib (LRCLIB REST API client)
```

### Key Design Decisions

**MediaRemote via swift interpreter**: Compiled binaries cannot access `MediaRemote.framework` (private framework). A helper swift script (`Resources/media-remote-helper.swift`) runs as a persistent subprocess via `/usr/bin/env swift`, streaming JSON over a pipe. This is the only way to get system-wide now-playing info.

**DI with swift-dependencies**: Protocol definitions + `DependencyKey` in `BackdropDomain`, `liveValue` registered in infrastructure modules. Config is resolved once at startup via `ConfigKey.liveValue` in `BackdropConfig`.

**TOML config with Int→Double coercion**: `FlexibleDouble.swift` handles TOML's strict typing where `12` is Int, not Double. Config errors show a macOS alert dialog via `UserNotifier`.

**Config structure**: `text.highlight` is a table with `color` (gradient array) + style properties (size, spacing, etc.), not a flat array.

### Version Management

Version is defined in `Sources/BackdropCLI/Resources/version.txt` (single source of truth). CI reads this file to auto-create/update git tags on push to main.
