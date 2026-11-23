---
description: "Lyra coverage architecture — excluded modules, live-construction placement, injected-seam inventory, deliberate exclusions."
trigger: glob
globs:
  - "Sources/**/*.swift"
  - "Tests/**/*.swift"
  - "codecov.yml"
  - "Package.swift"
---

# Coverage Architecture (lyra)

## Excluded modules

`codecov.yml` ignores `Sources/AppWiring`, `Sources/DependencyInjection`,
`Sources/Domain`, `Sources/LyraKit`. These hold wiring, contracts, and stubs
only — never implementation (see the global
`coverage-ignored-modules` rule).

## Where live construction lives

Module DAG: `CLI → App → AppRouter → DependencyInjection`. DI sits *below*
App/AppRouter, so it cannot construct App-layer types — the composition
root lives in `Sources/AppWiring` (leaf target above everything, also
excluded). All other `liveValue` construction lives in
`Sources/DependencyInjection`.

A `public init()` or default arg containing a live call inside a covered
module is a defect class (#362–#370): default-arg thunks attribute to the
declaring module and stay dead. Move it to an excluded module, or split
into `convenience init` (live calls, exercised through the injected path)
plus an internal injected `init` for tests.

Covered-module code must not name generated/concrete client types either
— an impl works through `any Xxx` (the Papyrus protocol), and the
concrete `XxxAPI` name belongs to the registration file alone
(`LLMMetadataDataSourceImpl` embedded `OpenAICompatibleAPI` until #370).
One-level factories (`OpenAICompatible.api(for:)`) keep the call site
flat without re-leaking the concrete into the impl.

Every outbound network path goes through `ScopedAPISession` (issues 318
and 370): API data sources, health-check runners, the remote wallpaper
download (`ScopedAPISession<URLSession>` where `API == URLSession`). No
process-lifetime `URLSession`, no hand-rolled ephemeral sessions (the
latter historically leaked one session per health-check run).

## Injected seams already in place

- `WallpaperPlaybackController(addPeriodicObserver:addItemEndObserver:)` —
  AVPlayer periodic + item-end registration
- `RipplePresenter(screenRect:addGlobalMonitor:removeGlobalMonitor:)` —
  `NSEvent.addGlobalMonitorForEvents` / `removeMonitor`
- `MediaRemoteDataSourceImpl(helperResourceURL:decodeBase64:)` —
  `Bundle.module.url` for the helper script
- `AppKitScreenProvider(windowInfoList:)` — `CGWindowListCopyWindowInfo`
- `DarwinGateway(lockDirectory:spawnProcess:)` — `Process.run`; a parked
  spy holds the launch/cancel race open for tests
- `ConfigDataSourceImpl(configHome:environment:)`,
  `ServiceHandlerImpl(launchAgentsPath:executablePath:)`,
  `WallpaperRepositoryImpl(cacheHome:)`

## Deliberate exclusions (uncoverable by invariant or OS boundary)

- `ConfigDataSourceImpl` `encodingFailed` — a fixed-value encode cannot fail
- `ConfigRepositoryImpl.healthCheck` `.unreadable` case — `validate` never
  produces it
- `CoreAudioTapGateway`, `AppWindow` `NSWindow` methods, `DisplayLinkDriver`,
  `FrameScheduler` `NSWindow` cast — OS-object calls CI cannot fire honestly
- `NowPlayingRepositoryImpl` pump-cancel exit, `WallpaperPresenter`
  empty-items guard — protected by invariants the public API cannot violate

Add an entry when a new structural exclusion is agreed — an unexplained
zero line reads as a gap, a named one as a decision.

## Measuring

`swift test` does not emit coverage. The recipe:

```sh
rm -rf .build/debug/codecov
swift test --enable-code-coverage
BIN=.build/debug/LyraPackageTests.xctest/Contents/MacOS/LyraPackageTests
PROF=.build/debug/codecov/default.profdata
xcrun llvm-cov report "$BIN" -instr-profile "$PROF" \
    -ignore-filename-regex 'Tests/'
xcrun llvm-cov show "$BIN" -instr-profile "$PROF" \
    -ignore-filename-regex 'Tests/' | grep -n " 0|"   # zero-execution lines
```
