// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Lyra",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "lyra", targets: ["CLI"]),
        // Library surface for external reuse — e.g. the planned `lyra-screensaver`
        // `.saver` bundle (#325), which reuses lyra's video-wallpaper pipeline rather
        // than re-implementing it. The product exposes the single `LyraKit` umbrella
        // target (below), which `@_exported import`s the reuse surface:
        //   • Entity / Domain — data types + `@Dependency` keys and protocols
        //   • Presenters       — `WallpaperPresenter` / `WallpaperPlaybackController`
        //                        (the AVPlayer loop/trim/cycle engine, NSWindow-free)
        //   • DependencyInjection — liveValue wiring so `@Dependency` resolves to the
        //                        real implementations without the consumer re-registering
        //                        the graph.
        // Product name ≠ importable module in SwiftPM (target names are the modules), so
        // the umbrella target lets a consumer write a single `import LyraKit`. A lighter
        // wallpaper-only product (splitting the DI registrations per feature so a consumer
        // can avoid linking MediaRemote/Audio) is a possible follow-up if the `.saver`
        // binary needs trimming; see #325.
        .library(name: "LyraKit", targets: ["LyraKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.6.0"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
        .package(url: "https://github.com/LebJe/TOMLKit", from: "0.6.0"),
        .package(url: "https://github.com/joshuawright11/papyrus", from: "0.6.16"),
        .package(url: "https://github.com/JohnSundell/Files", from: "4.2.0"),
        .package(url: "https://github.com/apple/swift-atomics", from: "1.2.0"),
    ],
    targets: [
        // ── CLI (Entry Point) ──
        .executableTarget(
            name: "CLI",
            dependencies: [
                "App",
                "AsyncRunnableCommand",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Dependencies", package: "swift-dependencies"),
            ],
            // Info.plist is embedded into the Mach-O __TEXT,__info_plist section
            // (see linkerSettings) rather than copied as a bundle resource, so it
            // is excluded from SwiftPM's resource processing here.
            exclude: ["Info.plist"],
            // Embed Info.plist so the binary carries a stable CFBundleIdentifier.
            // TCC keys permission grants (e.g. system-audio capture for the planned
            // spectrum analyzer, #23) by bundle identity; without an embedded plist
            // the grant is keyed to the executable path and resets on every reinstall.
            // The path is relative to the package root, where the linker is invoked.
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/CLI/Info.plist",
                ])
            ]
        ),

        // ── LyraKit (umbrella for external reuse, #325) ──
        // Pure `@_exported import` facade so a consumer of the `LyraKit` product
        // can `import LyraKit` once instead of importing each re-exported module.
        .target(
            name: "LyraKit",
            dependencies: [
                "Entity",
                "Domain",
                "Presenters",
                "DependencyInjection",
            ]
        ),

        // ── ProcessHandler ──
        .target(
            name: "ProcessHandler",
            dependencies: [
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),

        // ── ServiceHandler ──
        .target(
            name: "ServiceHandler",
            dependencies: [
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Files", package: "Files"),
            ]
        ),

        // ── HealthHandler ──
        .target(
            name: "HealthHandler",
            dependencies: [
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),

        // ── DarwinGateway ──
        .target(
            name: "DarwinGateway",
            dependencies: [
                "Domain"
            ]
        ),

        // ── CoreAudioTapGateway ──
        .target(
            name: "CoreAudioTapGateway",
            dependencies: [
                "Domain"
            ]
        ),

        // ── FileWatchGateway ──
        .target(
            name: "FileWatchGateway",
            dependencies: [
                "Domain"
            ]
        ),
        .target(
            name: "AppKitScreenProvider",
            dependencies: [
                "Domain"
            ]
        ),

        // ── RandomSource ──
        .target(
            name: "RandomSource",
            dependencies: [
                "Domain"
            ]
        ),

        // ── BenchmarkHandler ──
        .target(
            name: "BenchmarkHandler",
            dependencies: [
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),

        // ── ConfigHandler ──
        .target(
            name: "ConfigHandler",
            dependencies: [
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),

        // ── StandardOutput ──
        .target(
            name: "StandardOutput",
            dependencies: [
                "Domain"
            ]
        ),

        // ── TrackHandler ──
        .target(
            name: "TrackHandler",
            dependencies: [
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),

        // ── VersionHandler ──
        .target(
            name: "VersionHandler",
            dependencies: [
                "Domain"
            ],
            resources: [
                .copy("Resources/version.txt")
            ]
        ),

        // ── AsyncRunnableCommand ──
        .target(
            name: "AsyncRunnableCommand",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),

        // ── Router ──
        .target(
            name: "App",
            dependencies: [
                "AppRouter",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .target(
            name: "AppRouter",
            dependencies: [
                "Views",
                "Presenters",
                "Domain",
                "DependencyInjection",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),

        // ── View ──
        .target(
            name: "Views",
            dependencies: [
                "Domain",
                "Presenters",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),

        // ── Presenter ──
        .target(
            name: "Presenters",
            dependencies: [
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),

        // ── DI Wiring ──
        .target(
            name: "DependencyInjection",
            dependencies: [
                "AppKitScreenProvider",
                "Domain",
                "RandomSource",
                "TrackInteractor",
                "ScreenInteractor",
                "ConfigInteractor",
                "WallpaperInteractor",
                "SpectrumInteractor",
                "ConfigUseCase",
                "PlaybackUseCase",
                "LyricsUseCase",
                "MetadataUseCase",
                "WallpaperUseCase",
                "SpectrumUseCase",
                "ConfigRepository",
                "LyricsRepository",
                "MetadataRepository",
                "NowPlayingRepository",
                "WallpaperRepository",
                "AudioCaptureRepository",
                "ConfigDataSource",
                "LyricsDataSource",
                "MetadataDataSource",
                "MediaRemoteDataSource",
                "WallpaperDataSource",
                "AudioTapDataSource",
                "SQLiteDataStore",
                "DarwinGateway",
                "CoreAudioTapGateway",
                "FileWatchGateway",
                "FrequencyAnalyzer",
                "ProcessHandler",
                "VersionHandler",
                "ServiceHandler",
                "HealthHandler",
                "BenchmarkHandler",
                "TrackHandler",
                "ConfigHandler",
                "StandardOutput",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),

        // ── Interactor ──
        .target(
            name: "TrackInteractor",
            dependencies: [
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .target(
            name: "ScreenInteractor",
            dependencies: [
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .target(
            name: "ConfigInteractor",
            dependencies: [
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .target(
            name: "WallpaperInteractor",
            dependencies: [
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .target(
            name: "SpectrumInteractor",
            dependencies: [
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),

        // ── SpectrumUseCase ──
        .target(
            name: "SpectrumUseCase",
            dependencies: [
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),

        // ── AudioCaptureRepository ──
        .target(
            name: "AudioCaptureRepository",
            dependencies: [
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),

        // ── FrequencyAnalyzer ──
        .target(
            name: "FrequencyAnalyzer",
            dependencies: [
                "Domain"
            ]
        ),

        // ── UseCase ──
        .target(
            name: "ConfigUseCase",
            dependencies: [
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .target(
            name: "PlaybackUseCase",
            dependencies: [
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .target(
            name: "LyricsUseCase",
            dependencies: [
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .target(
            name: "MetadataUseCase",
            dependencies: [
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .target(
            name: "WallpaperUseCase",
            dependencies: [
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),

        // ── Repository ──
        .target(
            name: "ConfigRepository",
            dependencies: [
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .target(
            name: "LyricsRepository",
            dependencies: [
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .target(
            name: "MetadataRepository",
            dependencies: [
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .target(
            name: "NowPlayingRepository",
            dependencies: [
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .target(
            name: "WallpaperRepository",
            dependencies: [
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),

        // ── DataSource ──
        .target(
            name: "ConfigDataSource",
            dependencies: [
                "Domain",
                .product(name: "Files", package: "Files"),
                .product(name: "TOMLKit", package: "TOMLKit"),
            ]
        ),
        .target(name: "ScopedAPISession"),
        .target(
            name: "LyricsDataSource",
            dependencies: [
                "Domain",
                "ScopedAPISession",
                .product(name: "Papyrus", package: "papyrus"),
            ]
        ),
        .target(
            name: "MetadataDataSource",
            dependencies: [
                "Domain",
                "ScopedAPISession",
                .product(name: "Papyrus", package: "papyrus"),
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .target(
            name: "MediaRemoteDataSource",
            dependencies: [
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ],
            resources: [.copy("Resources/media-remote-helper.swift")]
        ),
        .target(
            name: "WallpaperDataSource",
            dependencies: [
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Files", package: "Files"),
            ]
        ),
        .target(
            name: "AudioTapDataSource",
            dependencies: [
                "Domain",
                .product(name: "Atomics", package: "swift-atomics"),
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),

        // ── DataStore ──
        .target(
            name: "SQLiteDataStore",
            dependencies: [
                "Domain",
                .product(name: "Files", package: "Files"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),

        // ── Domain ──
        .target(
            name: "Domain",
            dependencies: [
                "Entity",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),

        // ── Entity ──
        .target(
            name: "Entity",
            dependencies: []
        ),

        // ══ Tests ══

        .testTarget(
            name: "ScopedAPISessionTests",
            dependencies: [
                "ScopedAPISession"
            ]
        ),
        .testTarget(
            name: "TrackInteractorTests",
            dependencies: [
                "TrackInteractor",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "ScreenInteractorTests",
            dependencies: [
                "ScreenInteractor",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "ConfigInteractorTests",
            dependencies: [
                "ConfigInteractor",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "WallpaperInteractorTests",
            dependencies: [
                "WallpaperInteractor",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "WallpaperUseCaseTests",
            dependencies: [
                "WallpaperUseCase",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "SpectrumInteractorTests",
            dependencies: [
                "SpectrumInteractor",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "SpectrumUseCaseTests",
            dependencies: [
                "SpectrumUseCase",
                "Domain",
                "FrequencyAnalyzer",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "AudioCaptureRepositoryTests",
            dependencies: [
                "AudioCaptureRepository",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "FrequencyAnalyzerTests",
            dependencies: ["FrequencyAnalyzer", "Domain"]
        ),
        .testTarget(
            name: "AudioTapDataSourceTests",
            dependencies: [
                "AudioTapDataSource",
                "Domain",
            ]
        ),
        .testTarget(
            name: "CoreAudioTapGatewayTests",
            dependencies: ["CoreAudioTapGateway"]
        ),
        .testTarget(
            name: "FileWatchGatewayTests",
            dependencies: ["FileWatchGateway", "Domain"]
        ),
        .testTarget(name: "EntityTests", dependencies: ["Entity"]),
        .testTarget(
            name: "AsyncRunnableCommandTests",
            dependencies: [
                "AsyncRunnableCommand",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "CLITests",
            dependencies: [
                "App",
                "CLI",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(name: "AppTests", dependencies: ["App"]),
        .testTarget(name: "DarwinGatewayTests", dependencies: ["DarwinGateway"]),
        .testTarget(name: "AppKitScreenProviderTests", dependencies: ["AppKitScreenProvider", "Domain"]),
        .testTarget(name: "RandomSourceTests", dependencies: ["RandomSource", "Domain"]),
        .testTarget(
            name: "ProcessHandlerTests",
            dependencies: [
                "ProcessHandler",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(name: "VersionHandlerTests", dependencies: ["VersionHandler"]),
        .testTarget(
            name: "ServiceHandlerTests",
            dependencies: [
                "ServiceHandler",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "ConfigHandlerTests",
            dependencies: [
                "ConfigHandler",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "TrackHandlerTests",
            dependencies: [
                "TrackHandler",
                "LyricsUseCase",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "BenchmarkHandlerTests",
            dependencies: [
                "BenchmarkHandler",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "HealthHandlerTests",
            dependencies: [
                "HealthHandler",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "StandardOutputTests",
            dependencies: [
                "StandardOutput",
                "Domain",
            ]
        ),
        .testTarget(name: "ViewsTests", dependencies: ["Views", "Domain", "Presenters"]),
        .testTarget(
            name: "AppRouterTests",
            dependencies: [
                "AppRouter",
                "Presenters",
                "Views",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "PresentersTests",
            dependencies: [
                "Presenters",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "ConfigUseCaseTests",
            dependencies: [
                "ConfigUseCase",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "LyricsUseCaseTests",
            dependencies: [
                "LyricsUseCase",
                "MetadataUseCase",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "MetadataUseCaseTests",
            dependencies: [
                "MetadataUseCase",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "PlaybackUseCaseTests",
            dependencies: [
                "PlaybackUseCase",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "ConfigRepositoryTests",
            dependencies: [
                "ConfigRepository",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "LyricsRepositoryTests",
            dependencies: [
                "LyricsRepository",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "MetadataRepositoryTests",
            dependencies: [
                "MetadataRepository",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "NowPlayingRepositoryTests",
            dependencies: [
                "NowPlayingRepository",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "WallpaperRepositoryTests",
            dependencies: [
                "WallpaperRepository",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "ConfigDataSourceTests",
            dependencies: [
                "ConfigDataSource",
                "Domain",
                .product(name: "TOMLKit", package: "TOMLKit"),
            ]
        ),
        .testTarget(
            name: "ConfigHotReloadTests",
            dependencies: [
                "ConfigUseCase",
                "ConfigInteractor",
                "ConfigRepository",
                "ConfigDataSource",
                "Domain",
                "Entity",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "LyricsDataSourceTests",
            dependencies: [
                "LyricsDataSource",
                "Domain",
                "ConfigDataSource",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Papyrus", package: "papyrus"),
            ]
        ),
        .testTarget(
            name: "MetadataDataSourceTests",
            dependencies: [
                "MetadataDataSource",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Papyrus", package: "papyrus"),
            ]
        ),
        .testTarget(
            name: "MediaRemoteDataSourceTests",
            dependencies: [
                "MediaRemoteDataSource",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "WallpaperDataSourceTests",
            dependencies: [
                "WallpaperDataSource",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "SQLiteDataStoreTests",
            dependencies: [
                "SQLiteDataStore",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
    ]
)
