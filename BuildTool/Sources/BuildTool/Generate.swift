import BuildDescription
import Foundation

/// What `generate` makes for the build to use.
struct Generated {
    var build: Build
    var artifacts: [CMakeTarget: CMakeArtifacts]
    var downloads: [String: URL]
}

/// Everything SwiftPM needs before it can build `project` for `platform`:
/// Build.swift read, the CMake projects built, the downloads fetched, and
/// Package.swift written.
func generate(project: URL, for platform: any TargetPlatform) throws -> Generated {
    let work = project.appendingPathComponent(".build/buildtool")
    let description = try loadDescription(project: project, work: work, platform: platform.platform)

    let platformWork = work.appendingPathComponent(platform.platform.rawValue)
    var artifacts: [CMakeTarget: CMakeArtifacts] = [:]
    for cmakeProject in description.cmakeProjects {
        let built = try build(cmakeProject, for: platform, description: description, root: project, in: platformWork)
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
    return Generated(build: description, artifacts: artifacts, downloads: downloads)
}

/// Builds the executables, or the one whose product is `product`, as the
/// platform does, and copies each one's assets beside it.
func build(product: String?, swift: SwiftPM) throws {
    let generated = try generate(project: swift.project, for: swift.platform)
    let executables = generated.build.targets.filter {
        $0.kind == .executable && (product == nil || $0.product == product)
    }
    if let product, executables.isEmpty {
        throw BuildToolError("No executable product is named \(product)")
    }
    try swift.platform.buildExecutables(executables, generated: generated, swift: swift)

    let binPath = try swift.binPath()
    for target in executables {
        for asset in target.assets {
            guard let file = generated.downloads[asset] else { throw BuildToolError("No download is named \(asset)") }
            let destination = binPath.appendingPathComponent(asset)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: file, to: destination)
        }
    }
}

/// `target` and the targets it depends on, through theirs.
func closure(of target: Target, in build: Build) -> [Target] {
    let targets = Dictionary(uniqueKeysWithValues: build.targets.map { ($0.name, $0) })
    var visited = Set<String>()
    var result: [Target] = []
    func visit(_ target: Target) {
        guard visited.insert(target.name).inserted else { return }
        result.append(target)
        for case .target(let name) in target.dependencies {
            if let dependency = targets[name] { visit(dependency) }
        }
    }
    visit(target)
    return result
}
