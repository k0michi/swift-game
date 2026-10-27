import Foundation

// A Swift SDK installed for SwiftPM.
public struct SwiftSDK: Sendable {
    public let name: String
    public let sdksPath: String?

    public init(name: String, sdksPath: String?) {
        self.name = name
        self.sdksPath = sdksPath
    }

    var buildArguments: [String] {
        (sdksPath.map { ["--swift-sdks-path", $0] } ?? []) + ["--swift-sdk", name]
    }

    // A path from the SDK's configuration for a triple, such as sdkRootPath.
    func path(_ key: String, triple: String, swift: String) throws -> String {
        let configuration = try output(
            swift,
            ["sdk", "configure"] + (sdksPath.map { ["--swift-sdks-path", $0] } ?? [])
                + ["--show-configuration", name, triple]
        )
        guard let line = configuration.split(separator: "\n").first(where: { $0.hasPrefix("\(key): ") }) else {
            throw BuildError("The Swift SDK \(name) has no \(key) for \(triple)")
        }
        return String(line.dropFirst(key.count + 2))
    }
}

// swift build and swift test of the package for a platform, with the
// pkg-config files of its artifacts.
public struct SwiftBuild: Sendable {
    public let workspace: Workspace
    public let platform: Platform
    public let swift: String
    // Required for Emscripten.
    public let sdk: SwiftSDK?

    public init(workspace: Workspace, platform: Platform, swift: String, sdk: SwiftSDK?) {
        self.workspace = workspace
        self.platform = platform
        self.swift = swift
        self.sdk = sdk
    }

    public func build(configuration: String, _ arguments: [String]) throws {
        try run(swift, ["build"] + options(configuration: configuration) + arguments,
                in: workspace.root, environment: environment)
    }

    public func test(configuration: String, _ arguments: [String], environment extra: [String: String] = [:]) throws {
        try run(swift, ["test"] + options(configuration: configuration) + arguments,
                in: workspace.root, environment: environment.merging(extra) { $1 })
    }

    public func binDirectory(configuration: String) throws -> URL {
        URL(fileURLWithPath: try output(
            swift, ["build"] + options(configuration: configuration) + ["--show-bin-path"],
            in: workspace.root, environment: environment
        ))
    }

    // The manifest reads the environment, and the build plan holds the
    // pkg-config flags, neither of which SwiftPM tracks, so neither is
    // cached.
    private func options(configuration: String) throws -> [String] {
        var options = [
            "--configuration", configuration,
            "--manifest-cache", "none",
            "--disable-build-manifest-caching",
            "--pkg-config-path", workspace.pkgConfigDirectory(for: platform).path,
        ]
        if platform == .emscripten {
            guard let sdk else { throw BuildError("Building for Emscripten needs a Swift SDK") }
            options += sdk.buildArguments + [
                // The newer default, Swift Build, finds no platform for the
                // Emscripten triple, and the linker reads the native build
                // system's plan.
                "--build-system", "native",
                "--toolset", try emscriptenToolset().path,
                // SwiftPM takes the compiler for Apple's clang, but emcc
                // does not index.
                "--disable-index-store",
                // Emscripten's libc is musl, which hides much of POSIX behind
                // _GNU_SOURCE. Swift defines it for musl triples but not for
                // Emscripten, and Foundation only for platforms SwiftPM names.
                "-Xcc", "-D_GNU_SOURCE",
            ]
        }
        return options
    }

    private var environment: [String: String] {
        guard platform == .emscripten else { return [:] }
        return [
            "SWIFT_GAME_TARGET": "emscripten",
            "SWIFTCI_USE_LOCAL_DEPS": workspace.sourcesDirectory.path,
        ]
    }

    // Compiles C and C++ targets with emcc, which knows Emscripten's
    // sysroot and flags. SwiftPM finds the C compiler only by the name clang
    // in a toolset's root, which applies to the targets but not to host tools
    // such as macros, so the root holds clang and clang++ links to this
    // executable, which runs emcc and em++ when called by those names.
    private func emscriptenToolset() throws -> URL {
        let directory = workspace.artifactsDirectory(for: .emscripten).appendingPathComponent("toolset")
        let bin = directory.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() else {
            throw BuildError("Cannot find this executable")
        }
        for name in CompilerForwarding.names.keys {
            let link = bin.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: link)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: executable)
        }
        let file = directory.appendingPathComponent("toolset.json")
        try """
            {
              "schemaVersion": "1.0",
              "rootPath": "\(bin.path)"
            }

            """.write(to: file, atomically: true, encoding: .utf8)
        return file
    }
}

// Runs emcc or em++ in place of clang or clang++, for the toolset above.
public enum CompilerForwarding {
    static let names = ["clang": "emcc", "clang++": "em++"]

    // The command to run if this executable was called as a compiler.
    public static func forwardedCommand(for arguments: [String]) -> String? {
        arguments.first.flatMap { names[URL(fileURLWithPath: $0).lastPathComponent] }
    }

    public static func run(_ command: String, _ arguments: [String]) -> Never {
        do {
            try BuildSystem.run(command, arguments)
            exit(0)
        } catch let error as ProcessError {
            exit(error.status)
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(1)
        }
    }
}
