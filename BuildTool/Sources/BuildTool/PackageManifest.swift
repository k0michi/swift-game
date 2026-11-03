import BuildDescription

/// Package.swift for `build`, with the CMake targets' include directories and
/// libraries written into its targets' flags as absolute paths, so that SwiftPM
/// and Xcode build it as they would any package.
func packageManifest(for build: Build, artifacts: [CMakeTarget: CMakeArtifacts]) -> String {
    let targets = Dictionary(uniqueKeysWithValues: build.targets.map { ($0.name, $0) })

    // The include directories of the CMake targets that a target links, or
    // that any target it depends on does.
    func includeDirectories(of target: Target, visited: inout Set<String>) -> [String] {
        guard visited.insert(target.name).inserted else { return [] }
        var directories = target.linking.flatMap { artifacts[$0]?.includeDirectories ?? [] }
        for dependency in target.dependencies {
            if let dependency = targets[dependency] {
                directories += includeDirectories(of: dependency, visited: &visited)
            }
        }
        return directories
    }

    var lines = [
        "// swift-tools-version: 6.0",
        "",
        "// Written by BuildTool from Build.swift; change that instead.",
        "",
        "import PackageDescription",
        "",
        "let package = Package(",
        "    name: \(literal(build.name)),",
    ]
    if let macOSDeploymentTarget = build.macOSDeploymentTarget {
        lines.append("    platforms: [.macOS(\(literal(macOSDeploymentTarget)))],")
    }
    lines.append("    products: [")
    for target in build.targets where target.kind == .executable {
        lines.append("        .executable(name: \(literal(target.product ?? target.name)), targets: [\(literal(target.name))]),")
    }
    lines += ["    ],", "    targets: ["]
    for target in build.targets {
        var visited = Set<String>()
        let includes = unique(includeDirectories(of: target, visited: &visited))
        let libraries = unique(target.linking.flatMap { artifacts[$0]?.libraries ?? [] })

        let function =
            switch target.kind {
            case .regular: "target"
            case .executable: "executableTarget"
            case .test: "testTarget"
            }
        var arguments = ["name: \(literal(target.name))"]
        if !target.dependencies.isEmpty {
            arguments.append("dependencies: [\(target.dependencies.map(literal).joined(separator: ", "))]")
        }
        if let path = target.path {
            arguments.append("path: \(literal(path))")
        }
        if !includes.isEmpty {
            arguments.append("cSettings: [.unsafeFlags(\(array(includes.map { "-I\($0)" })))]")
            arguments.append("swiftSettings: [.unsafeFlags(\(array(includes.flatMap { ["-Xcc", "-I\($0)"] })))]")
        }
        if !libraries.isEmpty {
            arguments.append("linkerSettings: [.unsafeFlags(\(array(libraries)))]")
        }
        lines.append("        .\(function)(")
        lines.append(arguments.map { "            \($0)" }.joined(separator: ",\n"))
        lines.append("        ),")
    }
    lines += ["    ]", ")", ""]
    return lines.joined(separator: "\n")
}

private func literal(_ string: String) -> String {
    String(reflecting: string)
}

private func array(_ strings: [String]) -> String {
    "[" + strings.map(literal).joined(separator: ", ") + "]"
}
