import ArgumentParser
import BuildSystem
import Foundation

@main
enum Main {
    static func main() {
        // Progress goes to a pipe in CI, where buffering would put it out of
        // order with the commands' output and errors.
        setvbuf(stdout, nil, _IONBF, 0)
        let arguments = CommandLine.arguments
        if let command = CompilerForwarding.forwardedCommand(for: arguments) {
            CompilerForwarding.run(command, Array(arguments.dropFirst()))
        }
        Build.main()
    }
}

struct Build: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Builds swift-game and its native dependencies.",
        subcommands: [BuildProduct.self, Test.self, Serve.self, Dependencies.self],
        defaultSubcommand: BuildProduct.self
    )
}

// An executable product and the target it is made of.
struct Product {
    let name: String
    let target: String
    // The HTML page that the browser build is linked into.
    let shell: URL?
}

let game = Product(name: "swift-game", target: "SwiftGame", shell: nil)
let browserTests = Product(name: "EchoBrowserTests", target: "EchoBrowserTests", shell: nil)

struct Options: ParsableArguments {
    @Option(help: "What to build for: \(Platform.allCases.map(\.rawValue).joined(separator: ", ")).")
    var platform: Platform = .host

    @Option(name: .shortAndLong, help: "debug or release.")
    var configuration = "debug"

    // Such as a swift checkout made by update-checkout.
    @Option(help: "A directory with clones of the Git sources to fetch from (default: $SWIFT_GAME_SOURCE_MIRROR).")
    var sourceMirror: String?

    @Option(help: "The swift command to build with (default: $SWIFT, or swift).")
    var swift: String?

    @Option(help: "The swiftc that links for Emscripten (default: $SWIFT_EXEC, or swiftc).")
    var swiftc: String?

    @Option(help: "The Swift SDK for Emscripten (default: $SWIFT_EMSCRIPTEN_SDK).")
    var swiftSDK: String?

    @Option(name: .customLong("swift-sdks-path"), help: "Where the Swift SDK is installed (default: $SWIFT_SDKS_PATH, or SwiftPM's).")
    var swiftSDKsPath: String?

    @Argument(parsing: .postTerminator, help: "Arguments after -- for swift build or swift test.")
    var swiftArguments: [String] = []

    var workspace: Workspace {
        let mirror = sourceMirror ?? environment("SWIFT_GAME_SOURCE_MIRROR")
        return Workspace(root: packageRoot, sourceMirror: mirror.map { URL(fileURLWithPath: $0) })
    }

    func swiftBuild() throws -> SwiftBuild {
        var sdk: SwiftSDK?
        if platform == .emscripten {
            guard let name = swiftSDK ?? environment("SWIFT_EMSCRIPTEN_SDK") else {
                throw ValidationError("Building for Emscripten needs --swift-sdk or $SWIFT_EMSCRIPTEN_SDK.")
            }
            sdk = SwiftSDK(name: name, sdksPath: swiftSDKsPath ?? environment("SWIFT_SDKS_PATH"))
        }
        return SwiftBuild(
            workspace: workspace, platform: platform,
            swift: swift ?? environment("SWIFT") ?? "swift", sdk: sdk
        )
    }

    // Builds the artifacts and checks out the sources the platform needs,
    // and returns the artifacts' usages.
    func prepareDependencies() throws -> [ArtifactUsage] {
        if platform == .emscripten {
            for source in foundationSources {
                try source.checkout(in: workspace)
            }
        }
        let toolchain = try Toolchain.resolve(platform, macOSDeploymentTarget: "11.0")
        return try artifacts.filter { $0.platforms.contains(platform) }.map {
            try $0.prepare(for: toolchain, in: workspace)
        }
    }

    // Builds an executable product: for Emscripten, its target, linked
    // into a page.
    @discardableResult
    func build(_ product: Product) throws -> URL {
        let usages = try prepareDependencies()
        let build = try swiftBuild()
        switch platform {
        case .host:
            try build.build(configuration: configuration, ["--product", product.name] + swiftArguments)
            return try build.binDirectory(configuration: configuration).appendingPathComponent(product.name)
        case .emscripten:
            try build.build(configuration: configuration, ["--target", product.target] + swiftArguments)
            let linker = EmscriptenLinker(
                build: build, swiftc: swiftc ?? environment("SWIFT_EXEC") ?? "swiftc", usages: usages
            )
            return try linker.link(product: product.name, configuration: configuration, shell: product.shell)
        }
    }
}

struct BuildProduct: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Builds the game: an executable on the host, a page for Emscripten."
    )

    @OptionGroup var options: Options

    func run() throws {
        try options.build(game)
    }
}

struct Test: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Runs the tests: swift test on the host, Echo on Web Audio in headless Chromium for Emscripten."
    )

    @OptionGroup var options: Options

    func run() throws {
        switch options.platform {
        case .host:
            _ = try options.prepareDependencies()
            // SDL's tests need no display or audio device.
            try options.swiftBuild().test(
                configuration: options.configuration, options.swiftArguments,
                environment: ["SDL_VIDEODRIVER": "dummy", "SDL_AUDIODRIVER": "dummy"]
            )
        case .emscripten:
            let page = try options.build(browserTests)
            let tests = packageRoot.appendingPathComponent("Tests/EchoBrowserTests")
            if !FileManager.default.fileExists(atPath: tests.appendingPathComponent("node_modules").path) {
                try BuildSystem.run("npm", ["ci", "--prefix", tests.path, "--no-audit", "--no-fund"])
                try BuildSystem.run("npx", ["--prefix", tests.path, "playwright", "install", "chromium"])
            }
            try BuildSystem.run("node", [
                tests.appendingPathComponent("runner.js").path, page.deletingLastPathComponent().path,
            ])
        }
    }
}

struct Serve: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Builds the game for Emscripten and serves it on localhost."
    )

    @OptionGroup var options: Options

    @Option(help: "The port to serve on.")
    var port = 8000

    func validate() throws {
        guard options.platform == .emscripten else {
            throw ValidationError("Serve builds for the browser: pass --platform emscripten.")
        }
    }

    func run() throws {
        let page = try options.build(game)
        print("Serving http://localhost:\(port)/\(page.lastPathComponent)")
        try BuildSystem.run("python3", [
            "-m", "http.server", String(port), "--bind", "127.0.0.1",
            "--directory", page.deletingLastPathComponent().path,
        ])
    }
}

struct Dependencies: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Builds the artifacts and writes their pkg-config files, for builds outside this tool."
    )

    @OptionGroup var options: Options

    func run() throws {
        _ = try options.prepareDependencies()
        print("pkg-config files are in \(options.workspace.pkgConfigDirectory(for: options.platform).path)")
    }
}

extension Platform: ExpressibleByArgument {}

private func environment(_ name: String) -> String? {
    ProcessInfo.processInfo.environment[name].flatMap { $0.isEmpty ? nil : $0 }
}

// The swift-game package, which holds Tools.
let toolsRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let packageRoot = toolsRoot.deletingLastPathComponent()
let patchesDirectory = toolsRoot.appendingPathComponent("Patches")
