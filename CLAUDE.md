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

macOS desktop overlay app showing synced lyrics and video wallpaper. Clean Architecture with 12 Swift Package targets enforcing layer boundaries at compile time.

### Layer Dependency Flow

```
lyra (executable entry point)
  → CLI (ArgumentParser commands, ProcessManager, LaunchAgent)
    → App (AppDelegate, OverlayWindow — window management only)
      → Presentation (OverlayController, OverlayState, DecodeEffect)
        → Lyrics (cache→API→cache orchestration)
        → NowPlaying (MediaRemote notifications → AsyncStream)
      → Views (SwiftUI views — purely declarative, no logic)
      → Config (TOML/JSON config loading, text style resolution)
        → Domain (models, protocols, DependencyKeys)
  MediaRemote (isolated, no domain dependency)
  Persistence (GRDB SQLite cache)
  LyricsSearch (LRCLIB REST API client)
```

### Key Design Decisions

**MediaRemote via swift interpreter**: Compiled binaries cannot access `MediaRemote.framework` (private framework). A helper swift script (`Resources/media-remote-helper.swift`) runs as a persistent subprocess via `/usr/bin/env swift`, using `MRMediaRemoteRegisterForNowPlayingNotifications` for event-driven updates and streaming JSON over a pipe.

**Presentation / UI separation**: `Presentation` owns all state and logic (NowPlaying observation, lyrics fetching, decode animation timing, FetchState transitions). `Views` are purely declarative — they read display-ready strings from `OverlayState` and render them. `App.OverlayWindow` handles only window management.

**FetchState<T>**: Generic enum (`.idle`, `.loading`, `.revealing(T)`, `.success(T)`, `.failure`) drives both data flow and UI animation. The `.revealing` → `.success` transition is timed by `OverlayController` using `DecodeEffectState`.

**ColorStyle**: Domain-level enum (`.solid(hex)`, `.gradient([hex])`) enabling any text style to use either solid colors or gradients. Polymorphic TOML decoding supports both `color = "#FFF"` and `color = ["#AAA", "#BBB"]`.

**DI with swift-dependencies**: Protocol definitions + `DependencyKey` in `Domain`, `liveValue` registered in infrastructure modules. Config is resolved once at startup via `ConfigKey.liveValue` in `Config`.

**TOML config with Int→Double coercion**: `FlexibleDouble.swift` handles TOML's strict typing where `12` is Int, not Double. Config errors show a macOS alert dialog via `UserNotifier`.

### Version Management

Version is defined in `Sources/CLI/Resources/version.txt` (single source of truth). CI reads this file to auto-create/update git tags on push to main.
