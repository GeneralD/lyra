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
make lint                            # check formatting (swift-format)
make format                          # auto-fix formatting
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
            WallpaperUseCase[WallpaperUseCase]
        end

        subgraph Repository
            ConfigRepository[ConfigRepository]
            LyricsRepository[LyricsRepository]
            MetadataRepository[MetadataRepository]
            NowPlayingRepository[NowPlayingRepository]
            WallpaperRepository[WallpaperRepository]
        end

        subgraph DataSource
            LyricsDataSource[LyricsDataSource]
            MetadataDataSource[MetadataDataSource]
            ConfigDataSource[ConfigDataSource]
            MediaRemoteDataSource[MediaRemoteDataSource]
            WallpaperDataSource[WallpaperDataSource]
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
    MetadataRepository -.-> SQLiteDataStore
    WallpaperUseCase -.-> WallpaperRepository
    WallpaperRepository -.-> WallpaperDataSource

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
    style WallpaperUseCase fill:#59c,stroke:#333,color:#fff
    style ConfigRepository fill:#86c,stroke:#333,color:#fff
    style LyricsRepository fill:#86c,stroke:#333,color:#fff
    style MetadataRepository fill:#86c,stroke:#333,color:#fff
    style NowPlayingRepository fill:#86c,stroke:#333,color:#fff
    style WallpaperRepository fill:#86c,stroke:#333,color:#fff
    style LyricsDataSource fill:#c84,stroke:#333,color:#fff
    style MetadataDataSource fill:#c84,stroke:#333,color:#fff
    style ConfigDataSource fill:#c84,stroke:#333,color:#fff
    style MediaRemoteDataSource fill:#c84,stroke:#333,color:#fff
    style WallpaperDataSource fill:#c84,stroke:#333,color:#fff
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
| UseCase | `ConfigUseCase`, `PlaybackUseCase`, `LyricsUseCase`, `MetadataUseCase`, `WallpaperUseCase` | Business logic only, no cross-UseCase deps |
| Repository | `ConfigRepository`, `LyricsRepository`, `MetadataRepository`, `NowPlayingRepository`, `WallpaperRepository` | DataSource + DataStore orchestration, cache strategy |
| DataSource | `LyricsDataSource`, `MetadataDataSource`, `ConfigDataSource`, `MediaRemoteDataSource`, `WallpaperDataSource` | API execution, file I/O, private framework access |
| DataStore | `SQLiteDataStore` | GRDB SQLite cache |

### Key Design Decisions

**MediaRemoteDataSource via swift interpreter**: Compiled binaries cannot access `MediaRemote.framework` (private framework). A helper swift script (`Resources/media-remote-helper.swift`) runs as a persistent subprocess via `/usr/bin/env swift`, using `MRMediaRemoteRegisterForNowPlayingNotifications` for event-driven updates and streaming JSON over a pipe.

**Presentation / UI separation**: `Presentation` owns all state and logic (NowPlaying observation, lyrics fetching, decode animation timing, FetchState transitions). `Views` are purely declarative — they read display-ready strings from `OverlayState` and render them. `App.OverlayWindow` handles only window management.

**FetchState\<T\>**: Generic enum (`.idle`, `.loading`, `.revealing(T)`, `.success(T)`, `.failure`) drives both data flow and UI animation. The `.revealing` → `.success` transition is timed by `OverlayController` using `DecodeEffectState`.

**Entity types**: `AppStyle`, `TextLayout`, `TextAppearance`, `ArtworkStyle`, `RippleStyle`, `DecodeEffect`, `AIEndpoint`, `ColorStyle`, `HealthCheckResult`, `ConfigValidationResult`, `MusicBrainzMetadata`, `MediaRemotePollResult`, `LocalWallpaper`, `RemoteWallpaper`, `YouTubeWallpaper`. DI via `AppStyleKey` / `\.appStyle`.

**WallpaperDataSource\<LocationType\>**: Generic protocol defining `resolve(_ location: LocationType) async throws -> String`. Three implementations with distinct location types:
- `LocalWallpaperDataSourceImpl: WallpaperDataSource<LocalWallpaper>` — relative/absolute path resolution via Files library
- `RemoteWallpaperDataSourceImpl: WallpaperDataSource<RemoteWallpaper>` — HTTP(S) download with SHA256-keyed cache
- `YouTubeWallpaperDataSourceImpl: WallpaperDataSource<YouTubeWallpaper>` — yt-dlp/uvx download with H.264/AVC codec, SHA256-keyed cache

**WallpaperRepository URL classification**: Repository classifies wallpaper config string and dispatches to the appropriate DataSource. Priority: local path (no scheme) → YouTube URL (host contains youtube.com/youtu.be) → remote HTTP(S) URL. All paths converge to a local file path string.

**Wallpaper cache**: `~/.cache/lyra/wallpapers/SHA256(url).{ext}`. Cache is permanent (wallpapers are reused). `WallpaperCache` helper shared by Remote and YouTube DataSources.

**Wallpaper async resolution**: `OverlayWindow.init()` (already async) resolves wallpaper via `WallpaperUseCase` before creating AVPlayer. Config loads synchronously; only wallpaper download is async. Cached videos resolve instantly on subsequent launches.

**Domain Dependencies organization**: `Dependencies/` is organized by layer subdirectories (`UseCase/`, `Repository/`, `DataSource/`, `DataStore/`, `Misc/`) matching the architecture. Each file contains a protocol + `TestDependencyKey` + `DependencyValues` extension.

**Config layer**: Pure data — no AppKit imports. `Entity/Config/` contains `AppConfig`, `TextConfig`, `TextAppearanceConfig`, `ArtworkConfig`, `RippleConfig`, `DecodeEffectConfig`, `AIConfig`. Font metrics resolution lives in `DependencyInjection/AppStyleRegistration.swift`.

**Text style resolution**: `UnresolvedTextAppearance` (all-optional, private to `TextConfig.swift`) → variadic `resolve(defaults:filled:)` chain → `TextAppearanceConfig` (all non-optional). Layer defaults (title: bold/18pt, artist: medium, highlight: gold gradient) are applied via `Optional<UnresolvedTextAppearance>.resolve()`, ensuring defaults apply even when the TOML section is absent.

**FlexibleDouble**: `Codable` wrapper that decodes both TOML Int and Double via `singleValueContainer`. Used for all numeric config fields.

**MetadataDataSource\<Value\>**: Generic protocol defining `resolve(track:) -> [Value]`. Three implementations with distinct value types:
- `LLMMetadataDataSourceImpl: MetadataDataSource<Track>` — AI-based title/artist extraction
- `MusicBrainzMetadataDataSourceImpl: MetadataDataSource<MusicBrainzMetadata>` — MusicBrainz API lookup
- `RegexMetadataDataSourceImpl: MetadataDataSource<Track>` — regex-based title parsing and candidate generation

Each is injected individually into `MetadataRepository` (not as an array). Repository manages cache strategy and type conversion (`MusicBrainzMetadata → Track`).

**MetadataDataStore\<Value\>**: Generic cache protocol with `read(title:artist:) -> Value?` and `write(title:artist:value:)`. Two parameterizations:
- `MetadataDataStore<Track>` — LLM result cache (`GRDBLLMMetadataDataStore`)
- `MetadataDataStore<MusicBrainzMetadata>` — MusicBrainz result cache (`GRDBMetadataDataStore`)

Cache is Repository's responsibility, not DataSource's. DataSources are pure API/computation with no cache access.

**MetadataRepository cache strategy**: Priority order: LLM cache → LLM DataSource → MusicBrainz cache → MusicBrainz DataSource → Regex DataSource. LLM/MusicBrainz results are cached on success. Regex results are not cached.

**ColorStyle**: Domain-level enum (`.solid(hex)`, `.gradient([hex])`) enabling any text style to use either solid colors or gradients. Polymorphic TOML decoding supports both `color = "#FFF"` and `color = ["#AAA", "#BBB"]`.

**DI with swift-dependencies**: Protocol definitions + `TestDependencyKey` in `Domain`, all `liveValue` registrations centralized in `DependencyInjection` module. App style is resolved once at startup via `AppStyleKey.liveValue` in `DependencyInjection/AppStyleRegistration.swift`. No direct instantiation — everything through `@Dependency`.

**Config commands**: `lyra config template` (stdout), `lyra config init` (file creation), `lyra config edit` ($EDITOR), `lyra config open` (GUI). Template generation flows through UseCase→Repository→DataSource. `ConfigDataSource.template(format:)` encodes `AppConfig.defaults` via `TOMLEncoder`/`JSONEncoder`. `ConfigFormat` enum in Entity. `ConfigWriteError` for init failure handling.

**HealthCheckable**: Protocol in Domain with `serviceName` + `healthCheck()`. Implemented by `LRCLibAPI`, `MusicBrainzAPI`, `OpenAICompatibleAPI`. `lyra healthcheck` validates config, API connectivity, and AI token validity.

### Version Management

Version is defined in `Sources/CLI/Resources/version.txt` (single source of truth). CI reads this file to auto-create/update git tags on push to main.

**PR version bump rule**: When creating a PR, always include a version bump commit. Determine the level from the changes in the PR:
- `feat:` → minor bump
- `fix:` / `refactor:` / `chore:` → patch bump
- Breaking changes → major bump
