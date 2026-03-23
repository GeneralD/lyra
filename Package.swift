// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "lyra",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "lyra", targets: ["lyra"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.6.0"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
        .package(url: "https://github.com/LebJe/TOMLKit", from: "0.6.0"),
        .package(url: "https://github.com/thii/SwiftHEXColors", from: "1.4.1"),
        .package(url: "https://github.com/GeneralD/CollectionKit", from: "1.0.0"),
        .package(url: "https://github.com/Alamofire/Alamofire", from: "5.10.0"),
    ],
    targets: [
        // Core domain — zero external dependencies except swift-dependencies
        .target(
            name: "Domain",
            dependencies: [
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
            ]
        ),

        // Isolated unsafe code — no domain dependency
        .target(
            name: "MediaRemote",
            dependencies: [],
            resources: [.copy("Resources/media-remote-helper.swift")]
        ),

        // Infrastructure
        .target(
            name: "Config",
            dependencies: [
                "Domain",
                .product(name: "TOMLKit", package: "TOMLKit"),
            ]
        ),
        .target(
            name: "LRCLibService",
            dependencies: [
                "Domain",
                .product(name: "Alamofire", package: "Alamofire"),
            ]
        ),
        .target(
            name: "MusicBrainzService",
            dependencies: [
                "Domain",
                .product(name: "Alamofire", package: "Alamofire"),
            ]
        ),
        .target(
            name: "AIService",
            dependencies: ["Domain"]
        ),
        .target(
            name: "LyricsSearch",
            dependencies: [
                "Domain",
                "LRCLibService",
                .product(name: "Alamofire", package: "Alamofire"),
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .target(
            name: "MetadataNormalization",
            dependencies: [
                "Domain",
                "AIService",
                "MusicBrainzService",
                .product(name: "Alamofire", package: "Alamofire"),
                .product(name: "CollectionKit", package: "CollectionKit"),
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .target(
            name: "Persistence",
            dependencies: [
                "Domain",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),

        // Use cases
        .target(
            name: "NowPlaying",
            dependencies: ["Domain", "MediaRemote"]
        ),
        .target(
            name: "Lyrics",
            dependencies: ["Domain", "LyricsSearch", "Persistence", "MetadataNormalization"]
        ),

        // Presentation logic
        .target(
            name: "Presentation",
            dependencies: [
                "Domain",
                "Lyrics",
                "NowPlaying",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),

        // Views
        .target(
            name: "Views",
            dependencies: [
                "Domain",
                "Presentation",
                .product(name: "SwiftHEXColors", package: "SwiftHEXColors"),
                .product(name: "CollectionKit", package: "CollectionKit"),
            ]
        ),

        // App wiring
        .target(
            name: "App",
            dependencies: [
                "Views",
                "Presentation",
                "Config",
                "LRCLibService",
                "MusicBrainzService",
                "AIService",
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

        // Executable entry point
        .executableTarget(
            name: "lyra",
            dependencies: ["CLI"]
        ),

        // Tests
        .testTarget(
            name: "LyricsTests",
            dependencies: [
                "Lyrics",
                "LyricsSearch",
                "MetadataNormalization",
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
                "Config",
                .product(name: "TOMLKit", package: "TOMLKit"),
            ]
        ),
        .testTarget(
            name: "MetadataNormalizationTests",
            dependencies: [
                "MetadataNormalization",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: [
                "Persistence",
                "Domain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
    ]
)
