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
    ],
    targets: [
        // Core domain — zero external dependencies except swift-dependencies
        .target(
            name: "BackdropDomain",
            dependencies: [
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
            ]
        ),

        // Isolated unsafe code — no domain dependency
        .target(
            name: "BackdropMediaRemote",
            dependencies: []
        ),

        // Infrastructure
        .target(
            name: "BackdropConfig",
            dependencies: [
                "BackdropDomain",
                .product(name: "TOMLKit", package: "TOMLKit"),
            ]
        ),
        .target(
            name: "BackdropLRCLib",
            dependencies: ["BackdropDomain"]
        ),
        .target(
            name: "BackdropPersistence",
            dependencies: [
                "BackdropDomain",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),

        // Use cases
        .target(
            name: "BackdropNowPlaying",
            dependencies: ["BackdropDomain", "BackdropMediaRemote"]
        ),
        .target(
            name: "BackdropLyrics",
            dependencies: ["BackdropDomain", "BackdropLRCLib", "BackdropPersistence"]
        ),

        // Presentation
        .target(
            name: "BackdropUI",
            dependencies: ["BackdropDomain", "BackdropConfig"]
        ),

        // App wiring
        .target(
            name: "BackdropApp",
            dependencies: [
                "BackdropUI",
                "BackdropLyrics",
                "BackdropNowPlaying",
                "BackdropConfig",
                "BackdropPersistence",
                "BackdropLRCLib",
                "BackdropMediaRemote",
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
            name: "BackdropPersistenceTests",
            dependencies: [
                "BackdropPersistence",
                "BackdropDomain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
    ]
)
