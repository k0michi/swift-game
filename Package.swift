// swift-tools-version: 6.3

import PackageDescription
import Foundation

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
// The manifest is evaluated on the host and cannot see the Swift SDK being
// built for, so SWIFT_GAME_TARGET=emscripten selects the dependencies built
// for wasm32-unknown-emscripten.
let isEmscripten = ProcessInfo.processInfo.environment["SWIFT_GAME_TARGET"] == "emscripten"
let dependenciesRoot = "\(packageRoot)/.build/dependencies" + (isEmscripten ? "/emscripten" : "")
let sdlFlagsRoot = "\(dependenciesRoot)/sdl3"
let dawnFlagsRoot = "\(dependenciesRoot)/dawn"
let sdlBuildScript = isEmscripten ? "./scripts/emscripten/build-sdl.sh" : "./scripts/build-sdl.sh"
let dawnBuildScript = isEmscripten ? "./scripts/emscripten/build-dawn.sh" : "./scripts/build-dawn.sh"

func readSDLFlags(named name: String) -> [String] {
    let path = "\(sdlFlagsRoot)/\(name)-flags.txt"

    guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
        fatalError("SDL build metadata is missing. Run \(sdlBuildScript) first.")
    }

    return contents.split(whereSeparator: \.isNewline).map(String.init)
}

let sdlCompilerFlags = readSDLFlags(named: "compiler")
let sdlSwiftCompilerFlags = sdlCompilerFlags.flatMap { ["-Xcc", $0] }
let sdlLinkerFlags = readSDLFlags(named: "linker").flatMap { flag -> [String] in
    if flag == "-pthread" {
        return ["-lpthread"]
    }

    guard flag.hasPrefix("-Wl,") else {
        return [flag]
    }

    return flag.dropFirst(4).split(separator: ",").flatMap { ["-Xlinker", String($0)] }
}

func readDawnFlags(named name: String) -> [String] {
    let path = "\(dawnFlagsRoot)/\(name)-flags.txt"
    guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
        fatalError("Dawn build metadata is missing. Run \(dawnBuildScript) first.")
    }
    return contents.split(whereSeparator: \.isNewline).map(String.init)
}

let dawnCompilerFlags = readDawnFlags(named: "compiler")
let dawnSwiftCompilerFlags = dawnCompilerFlags.flatMap { ["-Xcc", $0] }
let dawnLinkerFlags = readDawnFlags(named: "linker").flatMap { flag -> [String] in
    if flag.contains("::") || flag.contains("$<") || flag == "dawn_public_config" || flag.contains("NOTFOUND") || ["debug", "optimized", "general"].contains(flag) {
        return []
    }
    if flag.hasPrefix("-framework ") {
        return ["-framework", String(flag.dropFirst("-framework ".count))]
    }
    if flag.hasPrefix("-Wl,") {
        return flag.dropFirst(4).split(separator: ",").flatMap { ["-Xlinker", String($0)] }
    }
    if flag.hasPrefix("-") || flag.hasPrefix("/") || flag.contains(":") {
        return [flag]
    }

    let libraryName = flag.hasSuffix(".lib") ? String(flag.dropLast(4)) : flag
    return ["-l\(libraryName)"]
}

// Echo plays through SDL3 on the desktop, and through the browser's Web Audio
// on the web.
let echoOutput: [Target.Dependency] = isEmscripten ? [] : ["EchoSDL3"]

// Fetch calls the browser's fetch on the web, and makes the requests itself
// with AsyncHTTPClient, on SwiftNIO, on the desktop.
let fetchDependencies: [Package.Dependency] = isEmscripten
    ? []
    : [
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.26.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.86.0"),
    ]
let fetchClient: [Target.Dependency] = isEmscripten
    ? []
    : [
        .product(name: "AsyncHTTPClient", package: "async-http-client"),
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOHTTP1", package: "swift-nio"),
    ]
let fetchTests: [Target] = isEmscripten
    ? []
    : [
        .testTarget(
            name: "FetchTests",
            dependencies: [
                "Fetch",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
            ]
        ),
    ]

let realModule: Target.Dependency = .product(name: "RealModule", package: "swift-numerics")

// Swift reads an executable's DefaultExecutorFactory, which MainLoop's
// browser executor needs, only when availability is not checked. Emscripten
// has no OS versions for availability to check.
let customExecutorSettings: [SwiftSetting] = isEmscripten
    ? [.unsafeFlags(["-Xfrontend", "-disable-availability-checking"])]
    : []

let package = Package(
    name: "SwiftGame",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "swift-game", targets: ["SwiftGame"]),
        .executable(name: "shooter", targets: ["Shooter"]),
        .library(name: "GameToolkit", targets: ["GameToolkit"]),
        .library(name: "SDL3", targets: ["SDL3"]),
        .library(name: "Dawn", targets: ["Dawn"]),
        .library(name: "SDL3Dawn", targets: ["SDL3Dawn"]),
        .library(name: "Interop", targets: ["Interop"]),
        .library(name: "Echo", targets: ["Echo"]),
        .library(name: "EchoSDL3", targets: ["EchoSDL3"]),
        .library(name: "MainLoop", targets: ["MainLoop"]),
        .library(name: "Fetch", targets: ["Fetch"]),
        .library(name: "VectorMath", targets: ["VectorMath"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-numerics.git", from: "1.1.0"),
    ] + fetchDependencies,
    targets: [
        .target(name: "Interop"),
        // Depends on nothing but the standard library and swift-numerics, so that
        // it can move to a package of its own. scripts/generate-vector-math.swift
        // writes most of it.
        .target(
            name: "VectorMath",
            dependencies: [.product(name: "RealModule", package: "swift-numerics")]
        ),
        .target(name: "CEmscripten"),
        // What was built, from scripts/generate-build-info.sh.
        .target(name: "CBuildInfo"),
        .target(name: "MainLoop", dependencies: ["CEmscripten"]),
        .target(name: "CEchoWeb"),
        .target(
            name: "Echo",
            dependencies: ["CEchoWeb", .product(name: "Atomics", package: "swift-atomics")]
        ),
        .target(name: "CFetchWeb"),
        // The Fetch API, kept apart from the rest so that only what makes
        // requests depends on SwiftNIO.
        .target(name: "Fetch", dependencies: ["CFetchWeb"] + fetchClient),
        // Swift targets that import SDL3 or Dawn, even indirectly, need their
        // headers to load CSDL3 or CDawn.
        .target(
            name: "EchoSDL3",
            dependencies: ["Echo", "SDL3"],
            swiftSettings: [.unsafeFlags(sdlSwiftCompilerFlags)]
        ),
        .target(
            name: "CSDL3",
            cSettings: [
                .unsafeFlags(sdlCompilerFlags),
            ],
            linkerSettings: [
                .unsafeFlags(sdlLinkerFlags),
            ]
        ),
        // Dawn is C++, and nothing else links the C++ standard library on
        // macOS.
        .target(
            name: "CDawn",
            cSettings: [.unsafeFlags(dawnCompilerFlags)],
            linkerSettings: [
                .unsafeFlags(dawnLinkerFlags),
                .linkedLibrary("c++", .when(platforms: [.macOS])),
            ]
        ),
        .target(
            name: "Dawn",
            dependencies: ["CDawn", "Interop"],
            swiftSettings: [.unsafeFlags(dawnSwiftCompilerFlags)]
        ),
        .target(
            name: "SDL3",
            dependencies: ["CSDL3", "Interop"],
            swiftSettings: [
                .unsafeFlags(sdlSwiftCompilerFlags),
            ]
        ),
        .target(
            name: "SDL3Dawn",
            dependencies: ["SDL3", "Dawn"],
            swiftSettings: [.unsafeFlags(sdlSwiftCompilerFlags + dawnSwiftCompilerFlags)]
        ),
        // Utilities on SDL3, WebGPU and Web Audio that games share: drawing
        // 2D shapes, 3D meshes and dot text, a debug overlay, and helpers that
        // hide what differs between the platforms.
        .target(
            name: "GameToolkit",
            dependencies: ["SDL3", "Dawn", "CBuildInfo", "VectorMath", "Echo", realModule] + echoOutput,
            swiftSettings: [
                .unsafeFlags(sdlSwiftCompilerFlags + dawnSwiftCompilerFlags),
            ]
        ),
        .executableTarget(
            name: "SwiftGame",
            dependencies: ["SDL3", "Dawn", "SDL3Dawn", "MainLoop", "VectorMath", "Echo", "GameToolkit", realModule],
            swiftSettings: [
                .unsafeFlags(sdlSwiftCompilerFlags + dawnSwiftCompilerFlags),
            ] + customExecutorSettings
        ),
        // A 3D shooting game, made of plain shapes.
        .executableTarget(
            name: "Shooter",
            dependencies: ["SDL3", "Dawn", "SDL3Dawn", "MainLoop", "VectorMath", "Echo", "GameToolkit", realModule],
            swiftSettings: [
                .unsafeFlags(sdlSwiftCompilerFlags + dawnSwiftCompilerFlags),
            ] + customExecutorSettings
        ),
        // Echo on the browser's Web Audio, run in headless Chromium by
        // scripts/emscripten/test-browser.sh.
        .executableTarget(
            name: "EchoBrowserTests",
            dependencies: ["Echo", "MainLoop"],
            path: "Tests/EchoBrowserTests",
            exclude: ["package.json", "package-lock.json", "node_modules", "runner.js"],
            swiftSettings: customExecutorSettings
        ),
        .testTarget(
            name: "DawnTests",
            dependencies: ["Dawn", "Interop"],
            swiftSettings: [
                .unsafeFlags(dawnSwiftCompilerFlags),
            ]
        ),
        .testTarget(
            name: "SDL3Tests",
            dependencies: ["SDL3"],
            swiftSettings: [
                .unsafeFlags(sdlSwiftCompilerFlags),
            ]
        ),
        .testTarget(
            name: "InteropTests",
            dependencies: ["Interop"]
        ),
        .testTarget(
            name: "ShooterTests",
            dependencies: ["Shooter", "VectorMath"],
            swiftSettings: [.unsafeFlags(sdlSwiftCompilerFlags + dawnSwiftCompilerFlags)]
        ),
        .testTarget(
            name: "VectorMathTests",
            dependencies: ["VectorMath"]
        ),
        // Counts a thread's heap allocations, for tests of the render path,
        // which must not allocate.
        .target(name: "CAllocationCounter", path: "Tests/CAllocationCounter"),
        .testTarget(
            name: "EchoTests",
            dependencies: ["Echo", "CAllocationCounter", .product(name: "Atomics", package: "swift-atomics")]
        ),
        .testTarget(
            name: "EchoSDL3Tests",
            dependencies: ["EchoSDL3", "Echo", "SDL3"],
            swiftSettings: [.unsafeFlags(sdlSwiftCompilerFlags)]
        ),
    ] + fetchTests
)
