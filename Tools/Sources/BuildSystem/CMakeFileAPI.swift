import Foundation

// Reads a target's compile and link information from CMake's File API:
// https://cmake.org/cmake/help/latest/manual/cmake-file-api.7.html
struct CMakeFileAPI {
    let buildDirectory: URL

    private var apiDirectory: URL { buildDirectory.appendingPathComponent(".cmake/api/v1") }
    private static let client = "client-swift-game"

    // Asks CMake to write the code model and the toolchains when it
    // configures.
    func writeQuery() throws {
        let directory = apiDirectory.appendingPathComponent("query").appendingPathComponent(Self.client)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let query = #"{"requests":[{"kind":"codemodel","version":2},{"kind":"toolchains","version":1}]}"#
        try query.write(to: directory.appendingPathComponent("query.json"), atomically: true, encoding: .utf8)
    }

    func usage(of targetName: String, platform: Platform) throws -> ArtifactUsage {
        let reply = apiDirectory.appendingPathComponent("reply")
        guard let indexName = try FileManager.default.contentsOfDirectory(atPath: reply.path)
            .filter({ $0.hasPrefix("index-") }).sorted().last
        else { throw BuildError("CMake wrote no File API reply in \(reply.path)") }
        let index = try decode(Index.self, reply.appendingPathComponent(indexName))
        guard let responses = index.reply[Self.client]?["query.json"]?.responses else {
            throw BuildError("The File API reply has no answer to \(Self.client)")
        }
        func response(_ kind: String) throws -> URL {
            guard let file = responses.first(where: { $0.kind == kind })?.jsonFile else {
                throw BuildError("The File API reply has no \(kind)")
            }
            return reply.appendingPathComponent(file)
        }

        let codemodel = try decode(Codemodel.self, response("codemodel"))
        guard let reference = codemodel.configurations.first?.targets.first(where: { $0.name == targetName }) else {
            throw BuildError("The code model has no target \(targetName)")
        }
        let target = try decode(Target.self, reply.appendingPathComponent(reference.jsonFile))

        var usage = ArtifactUsage()
        for group in target.compileGroups ?? [] {
            usage.append(group.usage)
        }
        guard let link = target.link else { return usage }
        usage.append(linkUsage(of: link.commandFragments))

        // Linking Swift does not bring in the C++ library that C++ code
        // needs, except on Apple platforms and Emscripten.
        #if os(Linux)
        if platform == .host, link.language == "CXX" {
            let toolchains = try decode(Toolchains.self, response("toolchains"))
            let implicit = toolchains.toolchains.first { $0.language == "CXX" }?.compiler.implicit
            usage.append(linkUsage(of: (implicit?.linkLibraries ?? []).map {
                Fragment(fragment: $0.hasPrefix("/") || $0.hasPrefix("-") ? $0 : "-l\($0)", role: "libraries")
            }))
        }
        #endif
        return usage
    }

    // Sorts link fragments into what pkg-config can carry and the rest.
    // The probe's own flags, which CMake gives the role "flags", are left out.
    private func linkUsage(of fragments: [Fragment]) -> ArtifactUsage {
        var usage = ArtifactUsage()
        for fragment in fragments where fragment.role != "flags" {
            // Linker options come as -Wl,a,b or -Xlinker a -Xlinker b.
            var words = fragment.fragment.split(separator: " ").map(String.init).filter { $0 != "-Xlinker" }
            if words.first?.hasPrefix("-Wl,") == true, words.count == 1 {
                words = words[0].dropFirst(4).split(separator: ",").map(String.init)
            }
            switch words.first {
            case "-framework" where words.count == 2:
                usage.frameworks.append(words[1])
            case "-weak_framework" where words.count == 2:
                // SwiftPM takes only -framework from pkg-config, and every
                // framework SDL weakly links exists on the deployment target.
                usage.frameworks.append(words[1])
            case "-pthread":
                usage.libraries.append("pthread")
            case let word? where fragment.role == "libraryPath" && word.hasPrefix("-L"):
                usage.libraryDirectories.append(String(word.dropFirst(2)))
            case let word? where fragment.role == "frameworkPath" && word.hasPrefix("-F"):
                usage.frameworkDirectories.append(String(word.dropFirst(2)))
            case let word? where word.hasPrefix("-l"):
                usage.libraries.append(String(word.dropFirst(2)))
            case let word? where !word.hasPrefix("-") && isLibraryFile(word):
                // Libraries built in the probe's tree are relative to it.
                let file = isAbsolute(word)
                    ? URL(fileURLWithPath: word)
                    : buildDirectory.appendingPathComponent(word).standardizedFileURL
                usage.libraryDirectories.append(file.deletingLastPathComponent().path)
                usage.libraries.append(libraryName(file.lastPathComponent))
            default:
                usage.linkerFlags.append(fragment.fragment)
            }
        }
        return usage
    }
}

// /a/b, or C:\a\b and C:/a/b on Windows.
private func isAbsolute(_ path: String) -> Bool {
    if path.hasPrefix("/") { return true }
    let characters = Array(path.utf8)
    return characters.count > 2 && characters[1] == UInt8(ascii: ":")
        && (characters[2] == UInt8(ascii: "\\") || characters[2] == UInt8(ascii: "/"))
}

private func isLibraryFile(_ path: String) -> Bool {
    [".a", ".so", ".dylib", ".lib", ".tbd"].contains { path.hasSuffix($0) }
}

// libSDL3.a → SDL3, and SDL3-static.lib → SDL3-static on Windows, where
// libraries have no lib prefix.
private func libraryName(_ file: String) -> String {
    var name = file
    if let dot = name.lastIndex(of: ".") { name = String(name[..<dot]) }
    #if !os(Windows)
    if name.hasPrefix("lib") { name.removeFirst(3) }
    #endif
    return name
}

private func decode<T: Decodable>(_ type: T.Type, _ file: URL) throws -> T {
    try JSONDecoder().decode(type, from: Data(contentsOf: file))
}

private struct Index: Decodable {
    struct Response: Decodable {
        let kind: String
        let jsonFile: String
    }

    struct ClientReply: Decodable {
        let responses: [Response]?
    }

    let reply: [String: [String: ClientReply]]

    private enum CodingKeys: CodingKey { case reply }

    init(from decoder: Decoder) throws {
        // The reply also holds entries for the shared queries, which are not
        // objects of client replies, so those are skipped.
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let all = try container.decode([String: Lenient<[String: Lenient<ClientReply>]>].self, forKey: .reply)
        reply = all.compactMapValues { $0.value?.compactMapValues(\.value) }
    }
}

private struct Lenient<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

private struct Codemodel: Decodable {
    struct Configuration: Decodable {
        let targets: [TargetReference]
    }

    struct TargetReference: Decodable {
        let name: String
        let jsonFile: String
    }

    let configurations: [Configuration]
}

private struct Fragment: Decodable {
    let fragment: String
    let role: String
}

private struct Target: Decodable {
    struct CompileGroup: Decodable {
        struct Include: Decodable { let path: String }
        struct Define: Decodable { let define: String }
        struct Framework: Decodable { let path: String }

        let includes: [Include]?
        let defines: [Define]?
        let frameworks: [Framework]?

        var usage: ArtifactUsage {
            var usage = ArtifactUsage()
            usage.includeDirectories = (includes ?? []).map(\.path)
            usage.defines = (defines ?? []).map(\.define)
            usage.frameworkDirectories = (frameworks ?? []).map { URL(fileURLWithPath: $0.path).deletingLastPathComponent().path }
            return usage
        }
    }

    struct Link: Decodable {
        let language: String
        let commandFragments: [Fragment]
    }

    let compileGroups: [CompileGroup]?
    let link: Link?
}

private struct Toolchains: Decodable {
    struct Toolchain: Decodable {
        struct Compiler: Decodable {
            struct Implicit: Decodable {
                let linkLibraries: [String]?
            }

            let implicit: Implicit
        }

        let language: String
        let compiler: Compiler
    }

    let toolchains: [Toolchain]
}
