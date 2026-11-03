import BuildDescription
import Foundation

/// Reads `Build.swift` in `project` for `platform`: compiles BuildDescription
/// into a library, compiles Build.swift against it, and runs it to write what
/// it declares, as SwiftPM does with Package.swift and PackageDescription.
func loadDescription(project: URL, work: URL, platform: Platform) throws -> Build {
    let manifest = project.appendingPathComponent("Build.swift")
    guard FileManager.default.fileExists(atPath: manifest.path) else {
        throw BuildToolError("\(manifest.path) is missing")
    }
    let directory = work.appendingPathComponent("description")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    // BuildDescription's sources, from where BuildTool was built.
    let sourceDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("BuildDescription")
    let sources = try FileManager.default.contentsOfDirectory(atPath: sourceDirectory.path)
        .filter { $0.hasSuffix(".swift") }.sorted()
        .map { sourceDirectory.appendingPathComponent($0) }
    // Built again by another compiler, whose modules this one cannot read.
    let compiler = directory.appendingPathComponent("compiler")
    let compilerVersion = try output(of: ["swiftc", "--version"])
    if (try? String(contentsOf: compiler, encoding: .utf8)) != compilerVersion {
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try compilerVersion.write(to: compiler, atomically: true, encoding: .utf8)
    }

    let library = directory.appendingPathComponent(staticLibraryName("BuildDescription"))
    if try isOutdated(library, inputs: sources) {
        try run(
            ["swiftc"] + (try hostSDKArguments())
                + ["-parse-as-library", "-module-name", "BuildDescription", "-emit-library", "-static"]
                + ["-emit-module", "-emit-module-path", directory.appendingPathComponent("BuildDescription.swiftmodule").path]
                + ["-o", library.path] + sources.map(\.path))
    }

    let executable = directory.appendingPathComponent(executableName("build-description"))
    if try isOutdated(executable, inputs: [manifest, library]) {
        try run(
            ["swiftc"] + (try hostSDKArguments())
                + ["-I", directory.path, "-L", directory.path, "-lBuildDescription", "-o", executable.path, manifest.path])
    }

    let json = work.appendingPathComponent("description.json")
    try? FileManager.default.removeItem(at: json)
    try run(
        [executable.path], in: project,
        environment: ["BUILDTOOL_DESCRIPTION_OUTPUT": json.path, "BUILDTOOL_PLATFORM": platform.rawValue])
    guard FileManager.default.fileExists(atPath: json.path) else {
        throw BuildToolError("Build.swift declares no Build")
    }
    return try JSONDecoder().decode(Build.self, from: Data(contentsOf: json))
}

/// Whether `output` is missing or older than any of `inputs`.
func isOutdated(_ output: URL, inputs: [URL]) throws -> Bool {
    guard let built = try? output.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
        return true
    }
    return try inputs.contains {
        try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate! > built
    }
}
