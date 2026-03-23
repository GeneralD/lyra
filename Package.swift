// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Lyra",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "lyra", targets: ["lyra"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.6.0"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
        .package(url: "https://github.com/LebJe/TOMLKit", from: "0.6.0"),
        .package(url: "https://github.com/GeneralD/CollectionKit", from: "1.0.0"),
        .package(url: "https://github.com/Alamofire/Alamofire", from: "5.10.0"),
    ],
    targets: [
        // Executable
        .executableTarget(
            name: "lyra",
            dependencies: ["CLI"]
        ),

        // CLI
        .target(
            name: "CLI",
            dependencies: [
                "App",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Dependencies", package: "swift-dependencies"),
            ],
            resources: [
                .copy("Resources/version.txt"),
            ]
        ),

        // View
        .target(
            name: "Views",
            dependencies: [
                "Domain",
                "Presentation",
                .product(name: "CollectionKit", package: "CollectionKit"),
            ]
        ),

        // Interactor (App wiring)
        .target(
            name: "App",
            dependencies: [
                "Views",
                "Presentation",
                "ConfigDataSource",
                "LyricsUseCase",
                "MetadataUseCase",
                "PlaybackUseCase",
                "LyricsDataSource",
                "MetadataDataSource",
                "MediaRemoteDataSource",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),

        // Presenter
        .target(
            name: "Presentation",
            dependencies: [
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),

        // Entity
        .target(
            name: "Domain",
            dependencies: [
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
            ]
        ),

        // UseCase
        .target(
            name: "LyricsUseCase",
            dependencies: [
                "Domain",
                "LyricsRepository",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .target(
            name: "MetadataUseCase",
            dependencies: [
                "Domain",
                "MetadataRepository",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .target(
            name: "PlaybackUseCase",
            dependencies: [
                "Domain",
                "NowPlayingRepository",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),

        // Repository
        .target(
            name: "LyricsRepository",
            dependencies: [
                "Domain",
                "SQLiteDataStore",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .target(
            name: "MetadataRepository",
            dependencies: [
                "Domain",
                "MetadataDataSource",
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

        // DataSource
        .target(
            name: "LyricsDataSource",
            dependencies: [
                "Domain",
                .product(name: "Alamofire", package: "Alamofire"),
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .target(
            name: "MetadataDataSource",
            dependencies: [
                "Domain",
                .product(name: "Alamofire", package: "Alamofire"),
                .product(name: "CollectionKit", package: "CollectionKit"),
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .target(
            name: "ConfigDataSource",
            dependencies: [
                "Domain",
                .product(name: "TOMLKit", package: "TOMLKit"),
            ]
        ),

        // DataStore
        .target(
            name: "SQLiteDataStore",
            dependencies: [
                "Domain",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),

        // Isolated
        .target(
            name: "MediaRemoteDataSource",
            dependencies: ["Domain"],
            resources: [.copy("Resources/media-remote-helper.swift")]
        ),

        // Tests — UseCase
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

        // Tests — Repository
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

        // Tests — DataSource
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
            name: "ConfigDataSourceTests",
            dependencies: [
                "ConfigDataSource",
                "Domain",
                .product(name: "TOMLKit", package: "TOMLKit"),
            ]
        ),

        // Tests — DataStore
        .testTarget(
            name: "SQLiteDataStoreTests",
            dependencies: [
                "SQLiteDataStore",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),

        // Tests — Presentation / View / CLI
        .testTarget(
            name: "PresentationTests",
            dependencies: [
                "Presentation",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "ViewsTests",
            dependencies: ["Views"]
        ),
        .testTarget(
            name: "CLITests",
            dependencies: ["CLI"]
        ),
    ]
)
