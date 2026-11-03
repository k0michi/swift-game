import BuildDescription
import Foundation

// buildtool [--project-path <path>] [--platform <platform>] [--swift-sdk <name>]
//           <command> [arguments for swift build]
//
//   generate        builds the CMake projects, downloads, and writes Package.swift
//   build           generates, runs swift build, and puts the assets beside the
//                   executables
//   run <product>   builds the product and runs it
//   test            generates, and runs swift test in Build.swift's test
//                   environment
//
// The platform is the host's, macOS, linux or windows, unless it is
// emscripten, which needs the Swift SDK for wasm32-unknown-emscripten to be
// named, and emcmake and emcc on the PATH.

struct Options {
    var project = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    var platform = Platform.host
    var swiftSDK: String?
    var command = "build"
    var arguments: [String] = []

    init(_ arguments: [String]) throws {
        var arguments = arguments
        while let option = arguments.first, option.hasPrefix("--"), arguments.count > 1 {
            let value = arguments[1]
            switch option {
            case "--project-path": project = URL(fileURLWithPath: value).standardizedFileURL
            case "--platform":
                guard let platform = Platform(rawValue: value) else {
                    throw BuildToolError("Unknown platform \(value)")
                }
                self.platform = platform
            case "--swift-sdk": swiftSDK = value
            default: throw BuildToolError("Unknown option \(option)")
            }
            arguments.removeFirst(2)
        }
        command = arguments.first ?? "build"
        self.arguments = Array(arguments.dropFirst())
    }
}

/// What a project is built with for a platform.
struct Context {
    let options: Options
    let work: URL
    let emscripten: Emscripten?

    var project: URL { options.project }

    init(_ options: Options) throws {
        self.options = options
        work = options.project.appendingPathComponent(".build/buildtool")
        if options.platform == .emscripten {
            guard let sdk = options.swiftSDK else {
                throw BuildToolError("Building for emscripten needs --swift-sdk")
            }
            emscripten = Emscripten(sdk: sdk, work: work.appendingPathComponent("emscripten"))
        } else {
            emscripten = nil
        }
    }

    // swift build or test, for the platform.
    func swift(_ subcommand: String, _ arguments: [String]) -> [String] {
        ["swift", subcommand, "--package-path", project.path] + (emscripten?.swiftBuildArguments ?? []) + arguments
    }

    var environment: [String: String] {
        get throws { try emscripten?.environment() ?? [:] }
    }

    // Where swift build puts what it builds with `arguments`.
    func binPath(_ arguments: [String]) throws -> URL {
        let path = try output(of: swift("build", ["--show-bin-path"] + arguments))
            .split(separator: "\n").last.map(String.init) ?? ""
        return URL(fileURLWithPath: path)
    }
}

/// What `generate` makes for the build to use.
struct Generated {
    var build: Build
    var artifacts: [CMakeTarget: CMakeArtifacts]
    var downloads: [String: URL]
}

// Everything SwiftPM needs before it can build.
func generate(_ context: Context) throws -> Generated {
    let platform = context.options.platform
    let description = try loadDescription(project: context.project, work: context.work, platform: platform)

    let work = context.work.appendingPathComponent(platform.rawValue)
    var artifacts: [CMakeTarget: CMakeArtifacts] = [:]
    for cmakeProject in description.cmakeProjects {
        let built = try build(
            cmakeProject, platform: platform, root: context.project, in: work,
            macOSDeploymentTarget: description.macOSDeploymentTarget)
        for (target, artifact) in built {
            artifacts[cmakeProject.target(target)] = artifact
        }
    }
    var downloads: [String: URL] = [:]
    for download in description.downloads {
        downloads[download.name] = try fetch(download, in: context.work)
    }

    // Unchanged, it is left alone, for SwiftPM and Xcode not to reload it.
    let manifest = context.project.appendingPathComponent("Package.swift")
    let contents = packageManifest(for: description, artifacts: artifacts)
    if (try? String(contentsOf: manifest, encoding: .utf8)) != contents {
        try contents.write(to: manifest, atomically: true, encoding: .utf8)
    }
    return Generated(build: description, artifacts: artifacts, downloads: downloads)
}

// Builds with swift build, or `product` alone, links for Emscripten, and
// copies each executable's assets beside it.
func build(_ context: Context, product: String?, _ arguments: [String]) throws {
    let generated = try generate(context)
    let executables = generated.build.targets.filter {
        $0.kind == .executable && (product == nil || $0.product == product)
    }
    if let product, executables.isEmpty {
        throw BuildToolError("No executable product is named \(product)")
    }
    let environment = try context.environment
    let binPath = try context.binPath(arguments)

    if let emscripten = context.emscripten {
        // Each executable's target alone, for SwiftPM not to link it.
        for target in executables {
            try run(context.swift("build", ["--target", target.name] + arguments), environment: environment)
            try emscripten.link(
                product: target.product ?? target.name, target: target, build: generated.build,
                artifacts: generated.artifacts, project: context.project,
                configuration: binPath.lastPathComponent, binPath: binPath)
        }
    } else {
        let products = product.map { ["--product", $0] } ?? []
        try run(context.swift("build", products + arguments), environment: environment)
    }

    for target in executables {
        for asset in target.assets {
            guard let file = generated.downloads[asset] else { throw BuildToolError("No download is named \(asset)") }
            let destination = binPath.appendingPathComponent(asset)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: file, to: destination)
        }
    }
}

do {
    let options = try Options(Array(CommandLine.arguments.dropFirst()))
    let context = try Context(options)
    var arguments = options.arguments
    switch options.command {
    case "generate":
        _ = try generate(context)
    case "build":
        // The product, which SwiftPM's --product names, is built alone.
        var product: String?
        if let index = arguments.firstIndex(of: "--product"), index + 1 < arguments.count {
            product = arguments[index + 1]
            arguments.removeSubrange(index...(index + 1))
        }
        try build(context, product: product, arguments)
    case "run":
        guard let product = arguments.first else { throw BuildToolError("run needs a product") }
        guard context.emscripten == nil else {
            throw BuildToolError("An emscripten build runs in a browser; build it and serve its bin path")
        }
        arguments.removeFirst()
        try build(context, product: product, arguments)
        try run([context.binPath(arguments).appendingPathComponent(executableName(product)).path])
    case "test":
        let generated = try generate(context)
        try run(
            context.swift("test", arguments),
            environment: try context.environment.merging(generated.build.testEnvironment) { $1 })
    default:
        throw BuildToolError("Unknown command \(options.command)")
    }
} catch {
    FileHandle.standardError.write(Data("buildtool: \(error)\n".utf8))
    exit(1)
}
