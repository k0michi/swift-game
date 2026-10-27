// swift-tools-version: 6.3

import PackageDescription
import Foundation

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
// The manifest is evaluated on the host and cannot see the Swift SDK being
// built for, so SWIFT_GAME_TARGET=emscripten selects the dependencies built
// for wasm32-unknown-emscripten. Tools/ sets it when it builds for the browser.
let isEmscripten = ProcessInfo.processInfo.environment["SWIFT_GAME_TARGET"] == "emscripten"

// Apple platforms ship Foundation. For Emscripten it is built from the sources
// that Tools checks out and patches.
let foundationDependencies: [Package.Dependency] = isEmscripten
    ? [.package(path: "\(packageRoot)/.build/sources/swift-corelibs-foundation")]
    : []
let foundation: [Target.Dependency] = isEmscripten
    ? [.product(name: "Foundation", package: "swift-corelibs-foundation")]
    : []

// Swift reads an executable's DefaultExecutorFactory, which MainLoop's
// browser executor needs, only when availability is not checked. Emscripten
// has no OS versions for availability to check.
let customExecutorSettings: [SwiftSetting] = isEmscripten
    ? [.unsafeFlags(["-Xfrontend", "-disable-availability-checking"])]
    : []

let package = Package(
    name: "SwiftGame",
    platforms: [
        .macOS(.v11),
    ],
    products: [
        .executable(name: "swift-game", targets: ["SwiftGame"]),
        .library(name: "SDL3", targets: ["SDL3"]),
        .library(name: "Dawn", targets: ["Dawn"]),
        .library(name: "SDL3Dawn", targets: ["SDL3Dawn"]),
        .library(name: "Interop", targets: ["Interop"]),
        .library(name: "Echo", targets: ["Echo"]),
        .library(name: "EchoSDL3", targets: ["EchoSDL3"]),
        .library(name: "MainLoop", targets: ["MainLoop"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.3.0"),
    ] + foundationDependencies,
    targets: [
        .target(name: "Interop"),
        .target(name: "CEmscripten"),
        .target(name: "MainLoop", dependencies: ["CEmscripten"]),
        .target(name: "CEchoWeb"),
        .target(
            name: "Echo",
            dependencies: ["CEchoWeb", .product(name: "Atomics", package: "swift-atomics")] + foundation
        ),
        .target(name: "EchoSDL3", dependencies: ["Echo", "SDL3"]),
        .systemLibrary(name: "CSDL3Library", pkgConfig: "swift-game-sdl3"),
        .target(name: "CSDL3", dependencies: ["CSDL3Library"]),
        .systemLibrary(name: "CDawnLibrary", pkgConfig: "swift-game-dawn"),
        .target(name: "CDawn", dependencies: ["CDawnLibrary"]),
        .target(
            name: "Dawn",
            dependencies: ["CDawn", "Interop"]
        ),
        .target(
            name: "SDL3",
            dependencies: ["CSDL3", "Interop"] + foundation
        ),
        .target(
            name: "SDL3Dawn",
            dependencies: ["SDL3", "Dawn"]
        ),
        .executableTarget(
            name: "SwiftGame",
            dependencies: ["SDL3", "Dawn", "SDL3Dawn", "MainLoop"],
            swiftSettings: customExecutorSettings
        ),
        // Echo on the browser's Web Audio, run in headless Chromium by
        // `swift run --package-path Tools build test --platform emscripten`.
        .executableTarget(
            name: "EchoBrowserTests",
            dependencies: ["Echo", "MainLoop"],
            path: "Tests/EchoBrowserTests",
            exclude: ["package.json", "package-lock.json", "node_modules", "runner.js"],
            swiftSettings: customExecutorSettings
        ),
        .testTarget(
            name: "DawnTests",
            dependencies: ["Dawn", "Interop"]
        ),
        .testTarget(
            name: "SDL3Tests",
            dependencies: ["SDL3"]
        ),
        .testTarget(
            name: "InteropTests",
            dependencies: ["Interop"]
        ),
        .testTarget(
            name: "EchoTests",
            dependencies: ["Echo"]
        ),
        .testTarget(
            name: "EchoSDL3Tests",
            dependencies: ["EchoSDL3", "Echo", "SDL3"]
        ),
    ]
)
