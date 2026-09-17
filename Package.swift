// swift-tools-version: 6.3

import PackageDescription
import Foundation

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let sdlFlagsRoot = "\(packageRoot)/.build/dependencies/sdl3"
let dawnFlagsRoot = "\(packageRoot)/.build/dependencies/dawn"

func readSDLFlags(named name: String) -> [String] {
    let path = "\(sdlFlagsRoot)/\(name)-flags.txt"

    guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
        fatalError("SDL build metadata is missing. Run ./scripts/build-sdl.sh first.")
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
        fatalError("Dawn build metadata is missing. Run ./scripts/build-dawn.sh first.")
    }
    return contents.split(whereSeparator: \.isNewline).map(String.init)
}

let dawnCompilerFlags = readDawnFlags(named: "compiler")
let dawnSwiftCompilerFlags = dawnCompilerFlags.flatMap { ["-Xcc", $0] }
let dawnLinkerFlags = readDawnFlags(named: "linker").flatMap { flag -> [String] in
    if flag.contains("::") || flag.contains("$<") || flag == "dawn_public_config" || flag.contains("NOTFOUND") {
        return []
    }
    if flag.hasPrefix("-framework ") {
        return ["-framework", String(flag.dropFirst("-framework ".count))]
    }
    guard flag.hasPrefix("-Wl,") else { return [flag] }
    return flag.dropFirst(4).split(separator: ",").flatMap { ["-Xlinker", String($0)] }
}

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
    ],
    targets: [
        .target(name: "Interop"),
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
            dependencies: ["CSDL3", "Interop"],
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
            dependencies: ["SDL3"],
            swiftSettings: [
                .unsafeFlags(sdlSwiftCompilerFlags),
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
    ]
)
