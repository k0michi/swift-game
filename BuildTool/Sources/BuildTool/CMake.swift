import BuildDescription
import Foundation

/// What a built CMake target gives the targets linking it.
struct CMakeArtifacts {
    var includeDirectories: [String]
    /// Flags for swiftc to link the target and all it needs.
    var linkerFlags: [String]
}

/// Fetches `project`, configures and builds its targets with Ninja for
/// `platform`, which chooses the compilers, and reads what they give what
/// links them from CMake's file API, with what the project declares besides.
func build(
    _ project: CMakeProject, for platform: any TargetPlatform, description: Build, root: URL, in work: URL
) throws -> [String: CMakeArtifacts] {
    let directory = work.appendingPathComponent("cmake").appendingPathComponent(project.name)
    let build = directory.appendingPathComponent("build")
    let source: URL
    switch project.source {
    case .git(let url, let revision):
        source = directory.appendingPathComponent("source")
        try fetch(url, revision: revision, into: source)
    case .path(let path):
        source = URL(fileURLWithPath: path, relativeTo: root).standardizedFileURL
    }

    // Asking for the code model before configuring has CMake write it. A new
    // query has Ninja configure again, so it is made only once.
    let query = build.appendingPathComponent(".cmake/api/v1/query/codemodel-v2")
    if !FileManager.default.fileExists(atPath: query.path) {
        try FileManager.default.createDirectory(at: query.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: query.path, contents: nil)
    }
    let probes = directory.appendingPathComponent("probes.cmake")
    // Left alone when unchanged, as Ninja configures again when it is newer.
    if (try? String(contentsOf: probes, encoding: .utf8)) != probeScript {
        try probeScript.write(to: probes, atomically: true, encoding: .utf8)
    }

    let configure = try platform.cmakeConfigureCommand(
        [
            "cmake", "-G", "Ninja", "-S", source.path, "-B", build.path, "--no-warn-unused-cli",
            "-DCMAKE_BUILD_TYPE=Release",
            "-DBUILD_SHARED_LIBS=OFF",
            "-DCMAKE_PROJECT_TOP_LEVEL_INCLUDES=\(probes.path)",
            "-DBUILDTOOL_TARGETS=\(project.targets.joined(separator: ";"))",
        ] + project.options.sorted { $0.key < $1.key }.map { "-D\($0.key)=\($0.value)" },
        build: description)

    // Configured again only when how it is configured, or the CMake doing it,
    // changes. Ninja configures again by itself when the project's own CMake
    // files change.
    let stamp = directory.appendingPathComponent("configured")
    let configuration =
        (configure + [try output(of: ["cmake", "--version"]), probeScript]).joined(separator: "\n")
    if (try? String(contentsOf: stamp, encoding: .utf8)) != configuration
        || !FileManager.default.fileExists(atPath: build.appendingPathComponent("CMakeCache.txt").path)
    {
        try? FileManager.default.removeItem(at: stamp)
        try run(configure)
        try configuration.write(to: stamp, atomically: true, encoding: .utf8)
    }
    try run(["cmake", "--build", build.path, "--parallel"] + project.targets.flatMap { ["--target", $0] })

    var artifacts = try readCodeModel(build: build, targets: project.targets, platform: platform)
    for target in project.targets {
        artifacts[target]!.includeDirectories += project.includeDirectories.map {
            URL(fileURLWithPath: $0, relativeTo: root).standardizedFileURL.path
        }
        artifacts[target]!.linkerFlags += project.linkerFlags
    }
    return artifacts
}

// For each target to read, an executable that links it and is never built:
// what CMake's file API says that executable compiles and links with is what
// the target gives what links it, through all it depends on.
private let probeScript = """
    # Written by BuildTool.
    cmake_language(DEFER CALL _buildtool_add_probes)
    function(_buildtool_add_probes)
        get_property(languages GLOBAL PROPERTY ENABLED_LANGUAGES)
        if("C" IN_LIST languages)
            set(source "${CMAKE_BINARY_DIR}/buildtool-probe.c")
        else()
            set(source "${CMAKE_BINARY_DIR}/buildtool-probe.cpp")
        endif()
        if(NOT EXISTS "${source}")
            file(WRITE "${source}" "int main(void) { return 0; }\\n")
        endif()
        foreach(target IN LISTS BUILDTOOL_TARGETS)
            string(MAKE_C_IDENTIFIER "${target}" identifier)
            add_executable(buildtool-probe-${identifier} EXCLUDE_FROM_ALL "${source}")
            target_link_libraries(buildtool-probe-${identifier} PRIVATE ${target})
        endforeach()
    endfunction()

    """

// A shallow fetch of the one revision, unless it is checked out already. The
// revision can be an annotated tag's, whose commit is what is checked out.
private func fetch(_ url: String, revision: String, into source: URL) throws {
    if FileManager.default.fileExists(atPath: source.appendingPathComponent(".git").path),
        let head = try? output(of: ["git", "-C", source.path, "rev-parse", "HEAD"]),
        let commit = try? output(of: ["git", "-C", source.path, "rev-parse", "--verify", "\(revision)^{commit}"]),
        head == commit
    {
        return
    }
    try? FileManager.default.removeItem(at: source)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try run(["git", "init", "--quiet"], in: source)
    try run(["git", "remote", "add", "origin", url], in: source)
    try run(["git", "fetch", "--quiet", "--depth", "1", "origin", revision], in: source)
    try run(["git", "checkout", "--quiet", "FETCH_HEAD"], in: source)
}

// Each target's probe's include directories, and its libraries and their
// search paths, without the probe's own linker flags.
private func readCodeModel(
    build: URL, targets: [String], platform: any TargetPlatform
) throws -> [String: CMakeArtifacts] {
    let reply = build.appendingPathComponent(".cmake/api/v1/reply")
    guard
        let index = try FileManager.default.contentsOfDirectory(atPath: reply.path)
            .filter({ $0.hasPrefix("index-") }).sorted().last
    else {
        throw BuildToolError("CMake wrote no file API reply in \(reply.path)")
    }
    let indexJSON = try readJSON(reply.appendingPathComponent(index))
    guard
        let codeModelFile = ((indexJSON["reply"] as? [String: Any])?["codemodel-v2"] as? [String: Any])?["jsonFile"]
            as? String
    else {
        throw BuildToolError("CMake's file API reply has no code model")
    }
    let codeModel = try readJSON(reply.appendingPathComponent(codeModelFile))
    let configuration = (codeModel["configurations"] as? [[String: Any]])?.first ?? [:]
    let files = Dictionary(
        (configuration["targets"] as? [[String: Any]] ?? []).compactMap { entry -> (String, String)? in
            guard let name = entry["name"] as? String, let file = entry["jsonFile"] as? String else { return nil }
            return (name, file)
        },
        uniquingKeysWith: { first, _ in first })

    var artifacts: [String: CMakeArtifacts] = [:]
    for target in targets {
        guard let file = files["buildtool-probe-\(cIdentifier(target))"] else {
            throw BuildToolError("CMake has no target \(target)")
        }
        let probe = try readJSON(reply.appendingPathComponent(file))
        let includes = (probe["compileGroups"] as? [[String: Any]] ?? [])
            .flatMap { $0["includes"] as? [[String: Any]] ?? [] }
            .compactMap { $0["path"] as? String }
        let fragments = ((probe["link"] as? [String: Any])?["commandFragments"] as? [[String: Any]] ?? [])
            .filter { ["libraries", "libraryPath", "frameworkPath"].contains($0["role"] as? String) }
            .compactMap { $0["fragment"] as? String }
        artifacts[target] = CMakeArtifacts(
            includeDirectories: unique(includes),
            linkerFlags: fragments.flatMap { fragment in
                platform.linkerFlags(fromFragment: words(fragment)) {
                    isAbsolutePath($0) ? $0 : build.appendingPathComponent($0).path
                }
            })
    }
    return artifacts
}

// The words of a fragment, which CMake quotes when they have spaces.
private func words(_ fragment: String) -> [String] {
    var words: [String] = []
    var word = ""
    var quoted = false
    for character in fragment {
        switch character {
        case "\"":
            quoted.toggle()
        case " " where !quoted:
            if !word.isEmpty { words.append(word) }
            word = ""
        default:
            word.append(character)
        }
    }
    if !word.isEmpty { words.append(word) }
    return words
}

// What CMake's string(MAKE_C_IDENTIFIER) makes of `string`.
private func cIdentifier(_ string: String) -> String {
    var identifier = String(string.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "_" })
    if identifier.first?.isNumber == true {
        identifier = "_" + identifier
    }
    return identifier
}

private func readJSON(_ url: URL) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
}

func unique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { seen.insert($0).inserted }
}
