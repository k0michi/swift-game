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

// Apple platforms ship Foundation. For Emscripten it is built from the sources
// that scripts/emscripten/fetch-foundation.sh checks out and patches.
let foundationDependencies: [Package.Dependency] = isEmscripten
    ? [.package(path: "\(dependenciesRoot)/foundation/swift-corelibs-foundation")]
    : []
let foundation: [Target.Dependency] = isEmscripten
    ? [.product(name: "Foundation", package: "swift-corelibs-foundation")]
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
        .target(name: "Echo", dependencies: [.product(name: "Atomics", package: "swift-atomics")] + foundation),
        .target(name: "EchoSDL3", dependencies: ["Echo", "SDL3"]),
        .target(
            name: "CSDL3",
            cSettings: [
                .unsafeFlags(sdlCompilerFlags),
            ],
            linkerSettings: [
                .unsafeFlags(sdlLinkerFlags),
            ]
        ),
        .target(
            name: "CDawn",
            cSettings: [.unsafeFlags(dawnCompilerFlags)],
            linkerSettings: [.unsafeFlags(dawnLinkerFlags)]
        ),
        .target(
            name: "Dawn",
            dependencies: ["CDawn", "Interop"],
            swiftSettings: [.unsafeFlags(dawnSwiftCompilerFlags)]
        ),
        .target(
            name: "SDL3",
            dependencies: ["CSDL3", "Interop"] + foundation,
            swiftSettings: [
                .unsafeFlags(sdlSwiftCompilerFlags),
            ]
        ),
        .target(
            name: "SDL3Dawn",
            dependencies: ["SDL3", "Dawn"]
        ),
        .executableTarget(
            name: "SwiftGame",
            dependencies: ["SDL3", "Dawn", "SDL3Dawn", "MainLoop"],
            swiftSettings: [
                .unsafeFlags(sdlSwiftCompilerFlags + dawnSwiftCompilerFlags),
            ]
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
            name: "EchoTests",
            dependencies: ["Echo"]
        ),
        .testTarget(
            name: "EchoSDL3Tests",
            dependencies: ["EchoSDL3", "Echo", "SDL3"]
        ),
    ]
)
