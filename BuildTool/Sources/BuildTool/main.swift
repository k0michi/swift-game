import BuildDescription
import Foundation

// buildtool [--project-path <path>] [--platform <platform>] [--swift-sdk <name>]
//           <command> [arguments for swift build]
//
//   generate        builds the CMake projects, downloads, and writes Package.swift
//   build           generates, builds the executables, and puts the assets
//                   beside them
//   run <product>   builds the product and runs it
//   test            generates, and runs swift test in Build.swift's test
//                   environment
//
// The platform is the host's, macOS, linux or windows, unless it is
// emscripten, which needs the Swift SDK for wasm32-unknown-emscripten to be
// named, and emcmake and emcc on the PATH.

do {
    let options = try Options(Array(CommandLine.arguments.dropFirst()))
    let platform = try targetPlatform(for: options.platform, options: options)
    var arguments = options.arguments
    switch options.command {
    case "generate":
        _ = try generate(project: options.project, for: platform)
    case "build":
        // The product, which SwiftPM's --product names, is built alone.
        var product: String?
        if let index = arguments.firstIndex(of: "--product"), index + 1 < arguments.count {
            product = arguments[index + 1]
            arguments.removeSubrange(index...(index + 1))
        }
        try build(product: product, swift: SwiftPM(project: options.project, platform: platform, arguments: arguments))
    case "run":
        guard let product = arguments.first else { throw BuildToolError("run needs a product") }
        let swift = SwiftPM(project: options.project, platform: platform, arguments: Array(arguments.dropFirst()))
        try build(product: product, swift: swift)
        try platform.run(product: product, swift: swift)
    case "test":
        let generated = try generate(project: options.project, for: platform)
        try run(
            SwiftPM(project: options.project, platform: platform, arguments: arguments).command("test"),
            environment: try platform.swiftEnvironment().merging(generated.build.testEnvironment) { $1 })
    default:
        throw BuildToolError("Unknown command \(options.command)")
    }
} catch {
    FileHandle.standardError.write(Data("buildtool: \(error)\n".utf8))
    exit(1)
}
