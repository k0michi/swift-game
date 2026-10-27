import Foundation

// Something built or downloaded once per platform that Swift targets compile
// against and link with.
public protocol Artifact: Sendable {
    var name: String { get }
    var platforms: Set<Platform> { get }
    // Everything the result depends on, so that a change rebuilds it.
    var fingerprint: String { get }

    // Builds the artifact into `directory` and returns how to use it.
    func build(for toolchain: Toolchain, into directory: URL, in workspace: Workspace) throws -> ArtifactUsage
}

extension Artifact {
    // Builds the artifact unless it is up to date, and writes its usage as
    // <name>.json and a pkg-config file <name>.pc for SwiftPM.
    @discardableResult
    public func prepare(for toolchain: Toolchain, in workspace: Workspace) throws -> ArtifactUsage {
        let directory = workspace.artifactsDirectory(for: toolchain.platform).appendingPathComponent(name)
        let usageFile = directory.appendingPathComponent("usage.json")
        let stampFile = directory.appendingPathComponent("stamp")
        let stamp = stableHash(fingerprint + "\n" + toolchain.cmakeArguments.joined(separator: "\n"))
        let usage: ArtifactUsage
        if (try? String(contentsOf: stampFile, encoding: .utf8)) == stamp,
           let data = try? Data(contentsOf: usageFile),
           let cached = try? JSONDecoder().decode(ArtifactUsage.self, from: data) {
            usage = cached
        } else {
            report("Building \(name) for \(toolchain.platform.rawValue)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            usage = try build(for: toolchain, into: directory, in: workspace)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(usage).write(to: usageFile)
            try stamp.write(to: stampFile, atomically: true, encoding: .utf8)
        }
        let pkgConfigDirectory = workspace.pkgConfigDirectory(for: toolchain.platform)
        try FileManager.default.createDirectory(at: pkgConfigDirectory, withIntermediateDirectories: true)
        try usage.pkgConfig(name: name).write(
            to: pkgConfigDirectory.appendingPathComponent("\(name).pc"), atomically: true, encoding: .utf8
        )
        return usage
    }
}

// FNV-1a, to name inputs; not for security.
func stableHash(_ string: String) -> String {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in string.utf8 {
        hash ^= UInt64(byte)
        hash &*= 0x100_0000_01b3
    }
    return String(hash, radix: 16)
}
