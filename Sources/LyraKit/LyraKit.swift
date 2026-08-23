// LyraKit — umbrella module for external reuse (#325).
//
// SwiftPM makes *target* names importable, not *product* names, so a product
// that merely bundles several targets would still force the consumer to write
// `import Domain` / `import Presenters` / `import DependencyInjection`
// separately. This umbrella target re-exports that reuse surface so a single
// `import LyraKit` is enough — the intended entry point for the planned
// `lyra-screensaver` `.saver` bundle, which reuses lyra's video-wallpaper
// pipeline rather than re-implementing it.
//
// Contains no logic of its own; it is a pure re-export facade (hence
// coverage-ignored, like Domain / DependencyInjection).

@_exported import DependencyInjection
@_exported import Domain
@_exported import Entity
@_exported import Presenters
