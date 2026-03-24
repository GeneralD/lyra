# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test

```sh
swift build                          # debug build
swift build -c release               # release build
swift test                           # run all tests
swift test --filter ConfigTests      # run single test suite
make build                           # release build via Makefile
make install                         # install to /usr/local/bin
```

## Architecture

macOS desktop overlay app showing synced lyrics and video wallpaper. VIPER + Clean Architecture with Swift Package targets enforcing layer boundaries at compile time.

### Module Dependency Graph

```mermaid
graph TD
    subgraph Entry
        lyra[lyra]
        CLI[CLI]
    end

    subgraph View
        Views[Views]
    end

    subgraph Interactor
        App[App]
    end

    subgraph DI Wiring
        DependencyInjection[DependencyInjection]
    end

    subgraph Presenter
        Presentation[Presentation]
    end

    subgraph DI Contract
        Domain[Domain]
    end

    subgraph Pure Model
        Entity[Entity]
    end

    subgraph Implementations
        subgraph UseCase
            ConfigUseCase[ConfigUseCase]
            PlaybackUseCase[PlaybackUseCase]
            LyricsUseCase[LyricsUseCase]
            MetadataUseCase[MetadataUseCase]
        end

        subgraph Repository
            ConfigRepository[ConfigRepository]
            LyricsRepository[LyricsRepository]
            MetadataRepository[MetadataRepository]
            NowPlayingRepository[NowPlayingRepository]
        end

        subgraph DataSource
            LyricsDataSource[LyricsDataSource]
            MetadataDataSource[MetadataDataSource]
            ConfigDataSource[ConfigDataSource]
            MediaRemoteDataSource[MediaRemoteDataSource]
        end

        subgraph DataStore
            SQLiteDataStore[SQLiteDataStore]
        end
    end

    lyra --> CLI
    CLI --> App
    App --> Views & Presentation & DependencyInjection
    DependencyInjection --> Implementations
    Views --> Presentation & Domain
    Presentation --> Domain
    Implementations --> Domain
    Domain --> Entity
    ConfigUseCase -.-> ConfigRepository
    ConfigRepository -.-> ConfigDataSource
    PlaybackUseCase -.-> NowPlayingRepository
    NowPlayingRepository -.-> MediaRemoteDataSource
    LyricsUseCase -.-> LyricsRepository
    LyricsRepository -.-> LyricsDataSource
    LyricsRepository -.-> SQLiteDataStore
    MetadataUseCase -.-> MetadataRepository
    MetadataRepository -.-> MetadataDataSource

    style lyra fill:#333,stroke:#333,color:#fff
    style CLI fill:#555,stroke:#333,color:#fff
    style App fill:#6a5,stroke:#333,color:#fff
    style Views fill:#6a5,stroke:#333,color:#fff
    style Presentation fill:#6a5,stroke:#333,color:#fff
    style DependencyInjection fill:#c44,stroke:#333,color:#fff
    style Entity fill:#4a9,stroke:#333,color:#fff
    style Domain fill:#38b,stroke:#333,color:#fff
    style ConfigUseCase fill:#59c,stroke:#333,color:#fff
    style PlaybackUseCase fill:#59c,stroke:#333,color:#fff
    style LyricsUseCase fill:#59c,stroke:#333,color:#fff
    style MetadataUseCase fill:#59c,stroke:#333,color:#fff
    style ConfigRepository fill:#86c,stroke:#333,color:#fff
    style LyricsRepository fill:#86c,stroke:#333,color:#fff
    style MetadataRepository fill:#86c,stroke:#333,color:#fff
    style NowPlayingRepository fill:#86c,stroke:#333,color:#fff
    style LyricsDataSource fill:#c84,stroke:#333,color:#fff
    style MetadataDataSource fill:#c84,stroke:#333,color:#fff
    style ConfigDataSource fill:#c84,stroke:#333,color:#fff
    style MediaRemoteDataSource fill:#c84,stroke:#333,color:#fff
    style SQLiteDataStore fill:#a75,stroke:#333,color:#fff
```

### Layer Summary (VIPER + Clean Architecture)

| Layer | Modules | Responsibility |
|---|---|---|
| Executable | `lyra` | Entry point |
| CLI | `CLI` | ArgumentParser commands, LaunchAgent |
| View | `Views` | SwiftUI views — purely declarative, no logic |
| DI Wiring | `DependencyInjection` | All liveValue registrations, FontMetrics, HealthCheck |
| Interactor | `App` | OverlayWindow management only |
| Presenter | `Presentation` | OverlayController, OverlayState, DecodeEffect, CharacterPool |
| Entity | `Entity` | Pure data types, zero external dependencies |
| Domain | `Domain` | Protocols, DependencyKeys (`@_exported import Entity`) |
| UseCase | `ConfigUseCase`, `PlaybackUseCase`, `LyricsUseCase`, `MetadataUseCase` | Business logic only, no cross-UseCase deps |
| Repository | `ConfigRepository`, `LyricsRepository`, `MetadataRepository`, `NowPlayingRepository` | DataSource + DataStore orchestration, cache strategy |
| DataSource | `LyricsDataSource`, `MetadataDataSource`, `ConfigDataSource`, `MediaRemoteDataSource` | API execution, file I/O, private framework access |
| DataStore | `SQLiteDataStore` | GRDB SQLite cache |

### Key Design Decisions

**MediaRemoteDataSource via swift interpreter**: Compiled binaries cannot access `MediaRemote.framework` (private framework). A helper swift script (`Resources/media-remote-helper.swift`) runs as a persistent subprocess via `/usr/bin/env swift`, using `MRMediaRemoteRegisterForNowPlayingNotifications` for event-driven updates and streaming JSON over a pipe.

**Presentation / UI separation**: `Presentation` owns all state and logic (NowPlaying observation, lyrics fetching, decode animation timing, FetchState transitions). `Views` are purely declarative — they read display-ready strings from `OverlayState` and render them. `App.OverlayWindow` handles only window management.

**FetchState\<T\>**: Generic enum (`.idle`, `.loading`, `.revealing(T)`, `.success(T)`, `.failure`) drives both data flow and UI animation. The `.revealing` → `.success` transition is timed by `OverlayController` using `DecodeEffectState`.

**Domain types**: `AppStyle`, `TextLayout`, `TextAppearance`, `ArtworkStyle`, `RippleStyle`, `DecodeEffect`, `AIEndpoint`, `ColorStyle`, `HealthCheckResult`, `ConfigValidationResult`, `MusicBrainzMetadata`, `MediaRemotePollResult`. DI via `AppStyleKey` / `\.appStyle`.

**Domain Dependencies organization**: `Dependencies/` is organized by layer subdirectories (`UseCase/`, `Repository/`, `DataSource/`, `DataStore/`, `Misc/`) matching the architecture. Each file contains a protocol + `TestDependencyKey` + `DependencyValues` extension.

**Config layer**: Pure data — no AppKit imports. `Entities/Config/` contains `AppConfig`, `TextConfig`, `TextAppearanceConfig`, `ArtworkConfig`, `RippleConfig`, `DecodeEffectConfig`, `AIConfig`. Font metrics resolution lives in `App/AppStyleBuilder.swift`.

**Text style resolution**: `UnresolvedTextAppearance` (all-optional, private to `TextConfig.swift`) → variadic `resolve(defaults:filled:)` chain → `TextAppearanceConfig` (all non-optional). Layer defaults (title: bold/18pt, artist: medium, highlight: gold gradient) are applied via `Optional<UnresolvedTextAppearance>.resolve()`, ensuring defaults apply even when the TOML section is absent.

**FlexibleDouble**: `Codable` wrapper that decodes both TOML Int and Double via `singleValueContainer`. Used for all numeric config fields.

**MetadataDataSource protocol**: Defines `resolve(track:) -> [Track]` for song metadata resolution. `LLMMetadataDataSourceImpl` (AI-based) and `MusicBrainzMetadataDataSourceImpl` (regex + MusicBrainz) are injected as `[any MetadataDataSource]` into `MetadataRepository`, which tries them in order. When LLM succeeds, MusicBrainz never runs.

**ColorStyle**: Domain-level enum (`.solid(hex)`, `.gradient([hex])`) enabling any text style to use either solid colors or gradients. Polymorphic TOML decoding supports both `color = "#FFF"` and `color = ["#AAA", "#BBB"]`.

**DI with swift-dependencies**: Protocol definitions + `TestDependencyKey` in `Domain`, `liveValue` registered in infrastructure modules via `DependencyKey` conformance. App style is resolved once at startup via `AppStyleKey.liveValue` in `App/AppStyleBuilder.swift`. No direct instantiation — everything through `@Dependency`.

**DataStore naming**: Cache protocols use `*DataStore` suffix (`AIMetadataDataStore`, `LyricsDataStore`, `MetadataDataStore`) to align with the architecture layer name, not `*CacheRepository`.

**HealthCheckable**: Protocol in Domain with `serviceName` + `healthCheck()`. Implemented by `LRCLibAPI`, `MusicBrainzAPI`, `OpenAICompatibleAPI`. `lyra healthcheck` validates config, API connectivity, and AI token validity.

### Version Management

Version is defined in `Sources/CLI/Resources/version.txt` (single source of truth). CI reads this file to auto-create/update git tags on push to main.
