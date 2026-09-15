// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SwiftGame",
    products: [
        .executable(name: "swift-game", targets: ["SwiftGame"])
    ],
    targets: [
        .executableTarget(name: "SwiftGame")
    ]
)
