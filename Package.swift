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
        // Core domain
        .target(
            name: "Domain",
            dependencies: [
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
            ]
        ),

        // Isolated
        .target(
            name: "MediaRemote",
            dependencies: [],
            resources: [.copy("Resources/media-remote-helper.swift")]
        ),

        // DataSource
        .target(
            name: "ConfigDataSource",
            dependencies: [
                "Domain",
                .product(name: "TOMLKit", package: "TOMLKit"),
            ]
        ),
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

        // DataStore
        .target(
            name: "SQLiteDataStore",
            dependencies: [
                "Domain",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),

        // Repository
        .target(
            name: "LyricsRepository",
            dependencies: [
                "Domain",
                "LyricsDataSource",
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

        // Repository
        .target(
            name: "NowPlayingRepository",
            dependencies: ["Domain", "MediaRemote"]
        ),

        // Use cases
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

        // Presentation
        .target(
            name: "Presentation",
            dependencies: [
                "Domain",
                "LyricsUseCase",
                "MetadataUseCase",
                "NowPlayingRepository",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),

        // Views
        .target(
            name: "Views",
            dependencies: [
                "Domain",
                "Presentation",
                .product(name: "CollectionKit", package: "CollectionKit"),
            ]
        ),

        // App wiring
        .target(
            name: "App",
            dependencies: [
                "Views",
                "Presentation",
                "ConfigDataSource",
                "LyricsDataSource",
                "MetadataDataSource",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
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

        // Executable
        .executableTarget(
            name: "lyra",
            dependencies: ["CLI"]
        ),

        // Tests
        .testTarget(
            name: "LyricsTests",
            dependencies: [
                "LyricsUseCase",
                "MetadataUseCase",
                "LyricsRepository",
                "MetadataRepository",
                "LyricsDataSource",
                "MetadataDataSource",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "CLITests",
            dependencies: ["CLI"]
        ),
        .testTarget(
            name: "PresentationTests",
            dependencies: [
                "Presentation",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "ConfigTests",
            dependencies: [
                "ConfigDataSource",
                .product(name: "TOMLKit", package: "TOMLKit"),
            ]
        ),
        .testTarget(
            name: "MetadataNormalizationTests",
            dependencies: [
                "MetadataDataSource",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: [
                "SQLiteDataStore",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "ViewsTests",
            dependencies: ["Views"]
        ),
    ]
)
