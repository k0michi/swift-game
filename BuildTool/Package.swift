// swift-tools-version: 6.0

import PackageDescription

// BuildTool reads a project's Build.swift, which declares its CMake projects,
// downloads and Swift targets, builds what SwiftPM cannot, and writes the
// project's Package.swift for SwiftPM and Xcode to build the rest.
let package = Package(
    name: "BuildTool",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "buildtool", targets: ["BuildTool"]),
        .library(name: "BuildDescription", targets: ["BuildDescription"]),
    ],
    targets: [
        // What Build.swift imports, and BuildTool reads back.
        .target(name: "BuildDescription"),
        .executableTarget(name: "BuildTool", dependencies: ["BuildDescription"]),
    ]
)
