import BuildDescription
import Foundation

// buildtool [--project-path <path>] <command> [arguments for swift build]
//
//   generate        builds the CMake projects, downloads, and writes Package.swift
//   build           generates, runs swift build, and puts the assets beside the
//                   executables
//   run <product>   builds the product and runs it
//   test            generates, and runs swift test in Build.swift's test
//                   environment

var arguments = Array(CommandLine.arguments.dropFirst())
var projectPath = FileManager.default.currentDirectoryPath
if arguments.first == "--project-path", arguments.count > 1 {
    projectPath = arguments[1]
    arguments.removeFirst(2)
}
let project = URL(fileURLWithPath: projectPath).standardizedFileURL
let command = arguments.first ?? "build"
let commandArguments = Array(arguments.dropFirst())

// Everything SwiftPM needs before it can build, and the downloads by name.
func generate(project: URL) throws -> (Build, [String: URL]) {
    let work = project.appendingPathComponent(".build/buildtool")
    let description = try loadDescription(project: project, work: work)

    var artifacts: [CMakeTarget: CMakeArtifacts] = [:]
    for cmakeProject in description.cmakeProjects {
        let built = try build(
            cmakeProject, root: project, in: work, macOSDeploymentTarget: description.macOSDeploymentTarget)
        for (target, artifact) in built {
            artifacts[cmakeProject.target(target)] = artifact
        }
    }
    var downloads: [String: URL] = [:]
    for download in description.downloads {
        downloads[download.name] = try fetch(download, in: work)
    }

    // Unchanged, it is left alone, for SwiftPM and Xcode not to reload it.
    let manifest = project.appendingPathComponent("Package.swift")
    let contents = packageManifest(for: description, artifacts: artifacts)
    if (try? String(contentsOf: manifest, encoding: .utf8)) != contents {
        try contents.write(to: manifest, atomically: true, encoding: .utf8)
    }
    return (description, downloads)
}

// Builds with swift build, and copies each executable's assets beside it.
func buildPackage(project: URL, _ swiftBuildArguments: [String]) throws {
    let (description, downloads) = try generate(project: project)
    try run(["swift", "build", "--package-path", project.path] + swiftBuildArguments)
    let binPath = try binPath(project: project, swiftBuildArguments)
    for target in description.targets {
        for asset in target.assets {
            guard let file = downloads[asset] else { throw BuildToolError("No download is named \(asset)") }
            let destination = URL(fileURLWithPath: binPath).appendingPathComponent(asset)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: file, to: destination)
        }
    }
}

// Where swift build puts what it builds with `swiftBuildArguments`.
func binPath(project: URL, _ swiftBuildArguments: [String]) throws -> String {
    try output(of: ["swift", "build", "--package-path", project.path, "--show-bin-path"] + swiftBuildArguments)
        .split(separator: "\n").last.map(String.init) ?? ""
}

do {
    switch command {
    case "generate":
        _ = try generate(project: project)
    case "build":
        try buildPackage(project: project, commandArguments)
    case "run":
        guard let product = commandArguments.first else { throw BuildToolError("run needs a product") }
        let swiftBuildArguments = Array(commandArguments.dropFirst())
        try buildPackage(project: project, ["--product", product] + swiftBuildArguments)
        let binPath = try binPath(project: project, swiftBuildArguments)
        try run([URL(fileURLWithPath: binPath).appendingPathComponent(product).path])
    case "test":
        let (description, _) = try generate(project: project)
        try run(
            ["swift", "test", "--package-path", project.path] + commandArguments,
            environment: description.testEnvironment)
    default:
        throw BuildToolError("Unknown command \(command)")
    }
} catch {
    FileHandle.standardError.write(Data("buildtool: \(error)\n".utf8))
    exit(1)
}
