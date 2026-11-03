import BuildDescription
import Foundation

/// Emscripten, with the Swift SDK for wasm32-unknown-emscripten that
/// `--swift-sdk` names, and emcmake and emcc on the PATH. SwiftPM compiles
/// the targets, and BuildTool links each executable into a page.
struct Emscripten: TargetPlatform {
    let sdk: String
    let work: URL

    init(options: Options) throws {
        guard let sdk = options.swiftSDK else {
            throw BuildToolError("Building for emscripten needs --swift-sdk")
        }
        self.sdk = sdk
        work = options.project.appendingPathComponent(".build/buildtool/emscripten")
    }

    var platform: Platform { .emscripten }

    func cmakeConfigureCommand(_ arguments: [String], build: Build) throws -> [String] {
        ["emcmake"] + arguments
    }

    // emcc's flags stay for emcc.
    func linkerFlags(fromFragment words: [String], resolve: (String) -> String) -> [String] {
        words.indices.map { words[$0].hasPrefix("-") || isFlagValue(words, at: $0) ? words[$0] : resolve(words[$0]) }
    }

    /// The native build system is the one that knows the Emscripten triple,
    /// and writes the plan that `link` reads.
    var swiftArguments: [String] {
        ["--swift-sdk", sdk, "--build-system", "native"]
    }

    /// SwiftPM compiles C targets with $CC for both the host, for build tools
    /// and macros, and the target, so $CC is a script that sends wasm32's to
    /// emcc and the rest to the toolchain's clang.
    func swiftEnvironment() throws -> [String: String] {
        let script = work.appendingPathComponent("cc")
        let contents = """
            #!/bin/sh
            # Written by BuildTool.
            for argument in "$@"; do
                case "$argument" in
                wasm32-unknown-emscripten | wasm64-unknown-emscripten)
                    exec "${EMCC:-emcc}" "$@"
                    ;;
                esac
            done
            exec "$BUILDTOOL_HOST_CC" "$@"

            """
        if (try? String(contentsOf: script, encoding: .utf8)) != contents {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            try contents.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        }
        let clang = try executable(named: "swiftc").deletingLastPathComponent().appendingPathComponent("clang")
        return ["CC": script.path, "BUILDTOOL_HOST_CC": clang.path]
    }

    // Each executable's target alone, for SwiftPM not to link it, and then
    // BuildTool's link.
    func buildExecutables(_ executables: [Target], generated: Generated, swift: SwiftPM) throws {
        let binPath = try swift.binPath()
        for target in executables {
            try BuildTool.run(swift.command("build", ["--target", target.name]), environment: swiftEnvironment())
            try link(
                product: target.product ?? target.name, target: target, generated: generated, project: swift.project,
                binPath: binPath)
        }
    }

    func run(product: String, swift: SwiftPM) throws {
        throw BuildToolError("An emscripten build runs in a browser; build it and serve its bin path")
    }

    /// Links the executable product `product` of `target` into HTML,
    /// JavaScript and wasm in `binPath`. SwiftPM's own link names its output
    /// .wasm, which has emcc make a standalone module without the JavaScript
    /// runtime, so the objects SwiftPM planned to link are linked here, with
    /// the libraries of the CMake targets that `target` and what it depends
    /// on link. Flags other than libraries go to emcc.
    private func link(product: String, target: Target, generated: Generated, project: URL, binPath: URL) throws {
        let objects = try plannedObjects(product: product, project: project, configuration: binPath.lastPathComponent)
        let list = work.appendingPathComponent("\(product).objects")
        try objects.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'\n" }.joined()
            .write(to: list, atomically: true, encoding: .utf8)

        var flags: [String] = []
        for target in closure(of: target, in: generated.build) {
            flags += target.linking.flatMap { generated.artifacts[$0]?.linkerFlags ?? [] } + target.linkerFlags
        }
        let linkerFlags = flags.flatMap { flag -> [String] in
            flag.hasPrefix("-l") || isAbsolutePath(flag) ? [flag] : ["-Xlinker-driver", flag]
        }

        let sdkRoot = try sdkPath("sdkRootPath")
        try BuildTool.run(
            [
                "swiftc", "-o", binPath.appendingPathComponent("\(product).html").path,
                "-module-name", product.replacingOccurrences(of: "-", with: "_"),
                "-emit-executable", "-target", "wasm32-unknown-emscripten", "-static-stdlib",
                "-sdk", sdkRoot, "-resource-dir", try sdkPath("swiftStaticResourcesPath"),
                "-tools-directory",
                URL(fileURLWithPath: sdkRoot).deletingLastPathComponent()
                    .appendingPathComponent("swift.xctoolchain/usr/bin").path,
                "-L", binPath.path, "@\(list.path)",
                // The Swift runtime is C++, which emcc links only when told to.
                "-Xlinker-driver", "-sDEFAULT_TO_CXX=1",
            ] + linkerFlags)
    }

    // The inputs of SwiftPM's link command for `product`, in its llbuild
    // manifest, but the module wrappers for debug information that are
    // planned and not always made.
    private func plannedObjects(product: String, project: URL, configuration: String) throws -> [String] {
        let manifest = try String(
            contentsOf: project.appendingPathComponent(".build/\(configuration).yaml"), encoding: .utf8)
        let node = "  \"C.\(product)-wasm32-unknown-emscripten-\(configuration).exe\":\n    tool: shell\n    inputs: "
        guard let start = manifest.range(of: node)?.upperBound,
            let end = manifest[start...].firstIndex(of: "\n"),
            let inputs = try JSONSerialization.jsonObject(with: Data(manifest[start..<end].utf8)) as? [String]
        else {
            throw BuildToolError("SwiftPM planned no link of \(product)")
        }
        let objects = inputs.filter {
            ($0.hasSuffix(".o") || $0.hasSuffix(".a"))
                && !($0.hasSuffix(".swiftmodule.o") && !FileManager.default.fileExists(atPath: $0))
        }
        let missing = objects.filter { !FileManager.default.fileExists(atPath: $0) }
        guard missing.isEmpty else {
            throw BuildToolError("SwiftPM did not build \(missing.joined(separator: ", "))")
        }
        return objects
    }

    // A path from the Swift SDK's configuration.
    private func sdkPath(_ key: String) throws -> String {
        let configuration = try output(
            of: ["swift", "sdk", "configure", "--show-configuration", sdk, "wasm32-unknown-emscripten"])
        for line in configuration.split(whereSeparator: \.isNewline) where line.hasPrefix("\(key): ") {
            return line.dropFirst(key.count + 2).trimmingCharacters(in: .whitespaces)
        }
        throw BuildToolError("The Swift SDK \(sdk) has no \(key)")
    }
}
