import BuildDescription
import Foundation

/// Reads `Build.swift` in `project`: compiles BuildDescription into a library,
/// compiles Build.swift against it, and runs it to write what it declares,
/// as SwiftPM does with Package.swift and PackageDescription.
func loadDescription(project: URL, work: URL) throws -> Build {
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
    let library = directory.appendingPathComponent("libBuildDescription.a")
    if try isOutdated(library, inputs: sources) {
        try run(
            ["swiftc", "-parse-as-library", "-module-name", "BuildDescription", "-emit-library", "-static",
             "-emit-module", "-emit-module-path", directory.appendingPathComponent("BuildDescription.swiftmodule").path,
             "-o", library.path] + sources.map(\.path))
    }

    let executable = directory.appendingPathComponent("build-description")
    if try isOutdated(executable, inputs: [manifest, library]) {
        try run(
            ["swiftc", "-I", directory.path, "-L", directory.path, "-lBuildDescription", "-o", executable.path,
             manifest.path])
    }

    let json = directory.appendingPathComponent("description.json")
    try? FileManager.default.removeItem(at: json)
    try run([executable.path], in: project, environment: ["BUILDTOOL_DESCRIPTION_OUTPUT": json.path])
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
