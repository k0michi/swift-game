import BuildDescription

/// Package.swift for `build`, with the CMake targets' include directories and
/// linker flags written into its targets' flags as absolute paths, so that
/// SwiftPM and Xcode build it as they would any package.
func packageManifest(for build: Build, artifacts: [CMakeTarget: CMakeArtifacts]) -> String {
    let targets = Dictionary(uniqueKeysWithValues: build.targets.map { ($0.name, $0) })

    // The include directories of the CMake targets that a target links, or
    // that any target it depends on does.
    func includeDirectories(of target: Target, visited: inout Set<String>) -> [String] {
        guard visited.insert(target.name).inserted else { return [] }
        var directories = target.linking.flatMap { artifacts[$0]?.includeDirectories ?? [] }
        for case .target(let name) in target.dependencies {
            if let dependency = targets[name] {
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
    for product in build.products {
        lines.append("        .library(name: \(literal(product.name)), targets: \(array(product.targets))),")
    }
    lines.append("    ],")
    if !build.dependencies.isEmpty {
        lines.append("    dependencies: [")
        for dependency in build.dependencies {
            lines.append("        .package(url: \(literal(dependency.url)), from: \(literal(dependency.from))),")
        }
        lines.append("    ],")
    }
    lines.append("    targets: [")
    for target in build.targets {
        var visited = Set<String>()
        let includes = unique(includeDirectories(of: target, visited: &visited))
        let cFlags = includes.map { "-I\($0)" } + target.cFlags
        let swiftFlags = includes.flatMap { ["-Xcc", "-I\($0)"] } + target.swiftFlags
        let linkerFlags = target.linking.flatMap { artifacts[$0]?.linkerFlags ?? [] } + target.linkerFlags

        let function =
            switch target.kind {
            case .regular: "target"
            case .executable: "executableTarget"
            case .test: "testTarget"
            }
        var arguments = ["name: \(literal(target.name))"]
        if !target.dependencies.isEmpty {
            arguments.append("dependencies: [\(target.dependencies.map(dependency).joined(separator: ", "))]")
        }
        if let path = target.path {
            arguments.append("path: \(literal(path))")
        }
        if !target.exclude.isEmpty {
            arguments.append("exclude: \(array(target.exclude))")
        }
        if !target.resources.isEmpty {
            arguments.append("resources: [\(target.resources.map(resource).joined(separator: ", "))]")
        }
        if !cFlags.isEmpty {
            arguments.append("cSettings: [.unsafeFlags(\(array(cFlags)))]")
        }
        if !swiftFlags.isEmpty {
            arguments.append("swiftSettings: [.unsafeFlags(\(array(swiftFlags)))]")
        }
        if !linkerFlags.isEmpty {
            arguments.append("linkerSettings: [.unsafeFlags(\(array(linkerFlags)))]")
        }
        lines.append("        .\(function)(")
        lines.append(arguments.map { "            \($0)" }.joined(separator: ",\n"))
        lines.append("        ),")
    }
    lines += ["    ]", ")", ""]
    return lines.joined(separator: "\n")
}

private func dependency(_ dependency: Dependency) -> String {
    switch dependency {
    case .target(let name): literal(name)
    case .product(let name, let package): ".product(name: \(literal(name)), package: \(literal(package)))"
    }
}

private func resource(_ resource: Resource) -> String {
    switch resource {
    case .copy(let path): ".copy(\(literal(path)))"
    case .process(let path): ".process(\(literal(path)))"
    }
}

private func literal(_ string: String) -> String {
    String(reflecting: string)
}

private func array(_ strings: [String]) -> String {
    "[" + strings.map(literal).joined(separator: ", ") + "]"
}
