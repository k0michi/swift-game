import BuildDescription
import Foundation

/// What a built CMake target gives the targets linking it.
struct CMakeArtifacts {
    var includeDirectories: [String]
    var libraries: [String]
}

/// Fetches `project` at its revision, configures and builds its targets with
/// Ninja and the Swift toolchain's clang, and reads where they are from
/// CMake's file API.
func build(_ project: CMakeProject, in work: URL, macOSDeploymentTarget: String?) throws -> [String: CMakeArtifacts] {
    let directory = work.appendingPathComponent("cmake").appendingPathComponent(project.name)
    let source = directory.appendingPathComponent("source")
    let build = directory.appendingPathComponent("build")
    try fetch(project, into: source)

    // Asking for the code model before configuring has CMake write it.
    let query = build.appendingPathComponent(".cmake/api/v1/query/codemodel-v2")
    try FileManager.default.createDirectory(at: query.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: query.path, contents: nil)

    let toolchain = try executable(named: "swiftc").deletingLastPathComponent()
    var configure = [
        "cmake", "-G", "Ninja", "-S", source.path, "-B", build.path, "--no-warn-unused-cli",
        "-DCMAKE_BUILD_TYPE=Release",
        "-DBUILD_SHARED_LIBS=OFF",
        "-DCMAKE_C_COMPILER=\(toolchain.appendingPathComponent("clang").path)",
        "-DCMAKE_CXX_COMPILER=\(toolchain.appendingPathComponent("clang++").path)",
    ]
    if let macOSDeploymentTarget {
        configure.append("-DCMAKE_OSX_DEPLOYMENT_TARGET=\(macOSDeploymentTarget)")
    }
    configure += project.options.sorted { $0.key < $1.key }.map { "-D\($0.key)=\($0.value)" }
    try run(configure)
    try run(["cmake", "--build", build.path, "--parallel"] + project.targets.flatMap { ["--target", $0] })

    return try readCodeModel(build: build, targets: project.targets)
}

// A shallow fetch of the one revision, unless it is checked out already.
private func fetch(_ project: CMakeProject, into source: URL) throws {
    if FileManager.default.fileExists(atPath: source.appendingPathComponent(".git").path),
        let head = try? output(of: ["git", "-C", source.path, "rev-parse", "HEAD"]),
        head.trimmingCharacters(in: .whitespacesAndNewlines) == project.revision
    {
        return
    }
    try? FileManager.default.removeItem(at: source)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try run(["git", "init", "--quiet"], in: source)
    try run(["git", "remote", "add", "origin", project.git], in: source)
    try run(["git", "fetch", "--quiet", "--depth", "1", "origin", project.revision], in: source)
    try run(["git", "checkout", "--quiet", "FETCH_HEAD"], in: source)
}

// The include directories each target compiles with, and its artifacts.
// The file API has no interface include directories, so those a target
// compiles with stand in for them.
private func readCodeModel(build: URL, targets: [String]) throws -> [String: CMakeArtifacts] {
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

    var artifacts: [String: CMakeArtifacts] = [:]
    for entry in configuration["targets"] as? [[String: Any]] ?? [] {
        guard let name = entry["name"] as? String, targets.contains(name), let file = entry["jsonFile"] as? String
        else { continue }
        let target = try readJSON(reply.appendingPathComponent(file))
        let includes = (target["compileGroups"] as? [[String: Any]] ?? [])
            .flatMap { $0["includes"] as? [[String: Any]] ?? [] }
            .compactMap { $0["path"] as? String }
        let libraries = (target["artifacts"] as? [[String: Any]] ?? [])
            .compactMap { $0["path"] as? String }
            .map { $0.hasPrefix("/") ? $0 : build.appendingPathComponent($0).path }
        artifacts[name] = CMakeArtifacts(includeDirectories: unique(includes), libraries: libraries)
    }
    for target in targets where artifacts[target] == nil {
        throw BuildToolError("CMake has no target \(target)")
    }
    return artifacts
}

private func readJSON(_ url: URL) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
}

func unique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { seen.insert($0).inserted }
}
