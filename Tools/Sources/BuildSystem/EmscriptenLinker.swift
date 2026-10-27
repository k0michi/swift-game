import Foundation

// Links an executable product that SwiftPM compiled for Emscripten into
// HTML, JavaScript and wasm. SwiftPM's own link step names the output .wasm,
// which makes emcc emit a standalone module without the JavaScript runtime,
// and does not link the C++ library, so the product is linked here from the
// objects SwiftPM planned.
public struct EmscriptenLinker: Sendable {
    public let build: SwiftBuild
    // The swiftc whose driver links: the one of the toolchain the SDK is for.
    public let swiftc: String
    public let usages: [ArtifactUsage]

    public init(build: SwiftBuild, swiftc: String, usages: [ArtifactUsage]) {
        self.build = build
        self.swiftc = swiftc
        self.usages = usages
    }

    @discardableResult
    public func link(product: String, configuration: String, shell: URL? = nil) throws -> URL {
        guard let sdk = build.sdk else { throw BuildError("Linking for Emscripten needs a Swift SDK") }
        let bin = try build.binDirectory(configuration: configuration)
        let triple = "wasm32-unknown-emscripten"
        let inputs = try plannedInputs(of: product, configuration: configuration)

        // CoreFoundation and Foundation go into an archive so that only what
        // is used is linked: the wasm build of Foundation leaves out RunLoop,
        // which the unused Timer code needs. Blocks come from CoreFoundation's
        // copy of the BlocksRuntime.
        let lazy = ["/CoreFoundation.build/", "/Foundation.build/"]
        var archived = inputs.filter { input in lazy.contains { input.contains($0) } }
        var objects = inputs.filter { input in !lazy.contains { input.contains($0) } }
        if !archived.isEmpty {
            let blocks = build.workspace.sourcesDirectory
                .appendingPathComponent("swift-corelibs-foundation/Sources/CoreFoundation")
            for file in ["data", "runtime"] {
                let object = bin.appendingPathComponent("BlocksRuntime-\(file).o")
                try run("emcc", [
                    "-I", blocks.appendingPathComponent("BlockRuntime/include").path,
                    "-I", blocks.appendingPathComponent("include").path,
                    "-c", blocks.appendingPathComponent("BlockRuntime/\(file).c").path,
                    "-o", object.path,
                ])
                archived.append(object.path)
            }
            let archive = bin.appendingPathComponent("lib\(product)-Foundation.a")
            try? FileManager.default.removeItem(at: archive)
            let members = try responseFile(archived, at: bin.appendingPathComponent("\(product).archived"))
            try run("emar", ["rcs", archive.path, "@" + members.path])
            objects.append(archive.path)
        }

        var usage = ArtifactUsage()
        for other in usages { usage.append(other) }
        let sdkRoot = try sdk.path("sdkRootPath", triple: triple, swift: build.swift)
        let output = bin.appendingPathComponent("\(product).html")
        var arguments = [
            "-o", output.path,
            "-module-name", product.replacingOccurrences(of: "-", with: "_"),
            "-emit-executable",
            "-target", triple,
            "-static-stdlib",
            "-sdk", sdkRoot,
            "-resource-dir", try sdk.path("swiftStaticResourcesPath", triple: triple, swift: build.swift),
            "-tools-directory", URL(fileURLWithPath: sdkRoot).deletingLastPathComponent()
                .appendingPathComponent("swift.xctoolchain/usr/bin").path,
            "-L", bin.path,
            "@" + (try responseFile(objects, at: bin.appendingPathComponent("\(product).objects"))).path,
        ]
        arguments += usage.libraryDirectories.flatMap { ["-L", $0] } + usage.libraries.map { "-l" + $0 }
        let emccFlags = ["-sDEFAULT_TO_CXX=1", "-sALLOW_MEMORY_GROWTH=1"]
            + usage.linkerFlags
            + (shell.map { ["--shell-file", $0.path] } ?? [])
        arguments += emccFlags.flatMap { ["-Xlinker-driver", $0] }
        try run(swiftc, arguments)
        report("Linked \(output.path)")
        return output
    }

    // The inputs of SwiftPM's link command for the product, from the
    // llbuild manifest it wrote. The module wrapper objects for debug info
    // are planned but not always made.
    private func plannedInputs(of product: String, configuration: String) throws -> [String] {
        let manifest = build.workspace.buildDirectory.appendingPathComponent("\(configuration).yaml")
        let contents = try String(contentsOf: manifest, encoding: .utf8)
        let node = "  \"C.\(product)-wasm32-unknown-emscripten-\(configuration).exe\":\n    tool: shell\n    inputs: "
        guard let start = contents.range(of: node)?.upperBound,
              let end = contents[start...].firstIndex(of: "\n")
        else { throw BuildError("\(manifest.path) has no link command for \(product)") }
        let inputs = try JSONDecoder().decode([String].self, from: Data(contents[start ..< end].utf8))
            .filter { $0.hasSuffix(".o") || $0.hasSuffix(".a") }
            .filter { !$0.hasSuffix(".swiftmodule.o") || FileManager.default.fileExists(atPath: $0) }
        let missing = inputs.filter { !FileManager.default.fileExists(atPath: $0) }
        guard missing.isEmpty else {
            throw BuildError("Missing objects:\n" + missing.joined(separator: "\n"))
        }
        return inputs
    }
}

private func responseFile(_ paths: [String], at file: URL) throws -> URL {
    let contents = paths.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: "\n")
    try (contents + "\n").write(to: file, atomically: true, encoding: .utf8)
    return file
}
