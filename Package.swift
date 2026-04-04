// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Lyra",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "lyra", targets: ["CLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.6.0"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
        .package(url: "https://github.com/LebJe/TOMLKit", from: "0.6.0"),
        .package(url: "https://github.com/Alamofire/Alamofire", from: "5.10.0"),
        .package(url: "https://github.com/JohnSundell/Files", from: "4.2.0"),
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
                .product(name: "Files", package: "Files"),
            ],
            resources: [
                .copy("Resources/version.txt"),
            ]
        ),

        // ── AsyncRunnableCommand ──
        .target(
            name: "AsyncRunnableCommand",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),

        // ── Router ──
        .target(
            name: "App",
            dependencies: [
                "Views",
                "Presenters",
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
                "Domain",
                "TrackInteractor",
                "ScreenInteractor",
                "WallpaperInteractor",
                "ConfigUseCase",
                "PlaybackUseCase",
                "LyricsUseCase",
                "MetadataUseCase",
                "WallpaperUseCase",
                "ConfigRepository",
                "LyricsRepository",
                "MetadataRepository",
                "NowPlayingRepository",
                "WallpaperRepository",
                "ConfigDataSource",
                "LyricsDataSource",
                "MetadataDataSource",
                "MediaRemoteDataSource",
                "WallpaperDataSource",
                "SQLiteDataStore",
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
            name: "WallpaperInteractor",
            dependencies: [
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
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
        .target(
            name: "LyricsDataSource",
            dependencies: [
                "Domain",
                .product(name: "Alamofire", package: "Alamofire"),
            ]
        ),
        .target(
            name: "MetadataDataSource",
            dependencies: [
                "Domain",
                .product(name: "Alamofire", package: "Alamofire"),
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .target(
            name: "MediaRemoteDataSource",
            dependencies: [
                "Domain",
                .product(name: "Files", package: "Files"),
            ],
            resources: [.copy("Resources/media-remote-helper.swift")]
        ),
        .target(
            name: "WallpaperDataSource",
            dependencies: [
                "Domain",
                .product(name: "Files", package: "Files"),
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
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
            ]
        ),

        // ── Entity ──
        .target(
            name: "Entity",
            dependencies: []
        ),

        // ══ Tests ══

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
        .testTarget(name: "EntityTests", dependencies: ["Entity"]),
        .testTarget(
            name: "AsyncRunnableCommandTests",
            dependencies: [
                "AsyncRunnableCommand",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "CLITests", dependencies: ["CLI"]),
        .testTarget(name: "ViewsTests", dependencies: ["Views", "Domain"]),
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
            name: "LyricsDataSourceTests",
            dependencies: [
                "LyricsDataSource",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "MetadataDataSourceTests",
            dependencies: [
                "MetadataDataSource",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "WallpaperDataSourceTests",
            dependencies: [
                "WallpaperDataSource",
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
