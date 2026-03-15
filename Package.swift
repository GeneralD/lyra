// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "backdrop",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "backdrop", targets: ["backdrop"]),
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
            name: "BackdropDomain",
            dependencies: [
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
                .product(name: "CollectionKit", package: "CollectionKit"),
            ]
        ),

        // Isolated unsafe code — no domain dependency
        .target(
            name: "BackdropMediaRemote",
            dependencies: [],
            resources: [.copy("Resources/media-remote-helper.swift")]
        ),

        // Infrastructure
        .target(
            name: "BackdropConfig",
            dependencies: [
                "BackdropDomain",
                .product(name: "TOMLKit", package: "TOMLKit"),
                .product(name: "SwiftHEXColors", package: "SwiftHEXColors"),
            ]
        ),
        .target(
            name: "BackdropLyricsSearch",
            dependencies: [
                "BackdropDomain",
                .product(name: "CollectionKit", package: "CollectionKit"),
                .product(name: "Alamofire", package: "Alamofire"),
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .target(
            name: "BackdropPersistence",
            dependencies: [
                "BackdropDomain",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),

        // Use cases
        .target(
            name: "BackdropNowPlaying",
            dependencies: ["BackdropDomain", "BackdropMediaRemote"]
        ),
        .target(
            name: "BackdropLyrics",
            dependencies: ["BackdropDomain", "BackdropLyricsSearch", "BackdropPersistence"]
        ),

        // Presentation logic
        .target(
            name: "BackdropPresentation",
            dependencies: [
                "BackdropDomain",
                "BackdropLyrics",
                "BackdropNowPlaying",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),

        // UI
        .target(
            name: "BackdropUI",
            dependencies: [
                "BackdropDomain",
                "BackdropPresentation",
                "BackdropConfig",
                .product(name: "SwiftHEXColors", package: "SwiftHEXColors"),
                .product(name: "CollectionKit", package: "CollectionKit"),
            ]
        ),

        // App wiring
        .target(
            name: "BackdropApp",
            dependencies: [
                "BackdropUI",
                "BackdropPresentation",
                "BackdropConfig",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),

        // CLI
        .target(
            name: "BackdropCLI",
            dependencies: [
                "BackdropApp",
                "BackdropConfig",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Dependencies", package: "swift-dependencies"),
            ],
            resources: [
                .copy("Resources/version.txt"),
            ]
        ),

        // Executable entry point
        .executableTarget(
            name: "backdrop",
            dependencies: ["BackdropCLI"]
        ),

        // Tests
        .testTarget(
            name: "BackdropDomainTests",
            dependencies: ["BackdropDomain"]
        ),
        .testTarget(
            name: "BackdropLyricsTests",
            dependencies: [
                "BackdropLyrics",
                "BackdropDomain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "BackdropCLITests",
            dependencies: ["BackdropCLI"]
        ),
        .testTarget(
            name: "BackdropPresentationTests",
            dependencies: [
                "BackdropPresentation",
                "BackdropDomain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "BackdropPersistenceTests",
            dependencies: [
                "BackdropPersistence",
                "BackdropDomain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
    ]
)
