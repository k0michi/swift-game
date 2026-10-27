// swift-tools-version: 6.0

import PackageDescription

// Builds swift-game's native dependencies and the game itself:
// swift run --package-path Tools build --help
let package = Package(
    name: "SwiftGameTools",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "build", targets: ["Build"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        // Artifacts built with CMake or downloaded, exposed to SwiftPM as
        // pkg-config files, and the commands that build and link products.
        .target(name: "BuildSystem"),
        // swift-game's artifacts and the command line.
        .executableTarget(
            name: "Build",
            dependencies: [
                "BuildSystem",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
