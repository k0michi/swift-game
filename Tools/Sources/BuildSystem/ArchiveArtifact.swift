import Foundation

// A zip archive downloaded and checked against its SHA-256 digest, whose
// usage is described by the closure given the extracted directory.
public struct ArchiveArtifact: Artifact {
    public let name: String
    public let url: String
    public let sha256: String
    public let platforms: Set<Platform>
    public let usage: @Sendable (_ directory: URL) -> ArtifactUsage

    public init(
        _ name: String,
        url: String,
        sha256: String,
        platforms: Set<Platform> = Set(Platform.allCases),
        usage: @escaping @Sendable (_ directory: URL) -> ArtifactUsage
    ) {
        self.name = name
        self.url = url
        self.sha256 = sha256
        self.platforms = platforms
        self.usage = usage
    }

    public var fingerprint: String { url + "\n" + sha256 }

    public func build(for toolchain: Toolchain, into directory: URL, in workspace: Workspace) throws -> ArtifactUsage {
        let archive = directory.appendingPathComponent("archive.zip")
        let contents = directory.appendingPathComponent("contents")
        print("Downloading \(url)")
        try run("curl", ["-fsSL", "-o", archive.path, url])
        let digest = BuildSystem.sha256(try Data(contentsOf: archive))
        guard digest == sha256 else {
            throw BuildError("\(url) has SHA-256 \(digest), expected \(sha256)")
        }
        try? FileManager.default.removeItem(at: contents)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        #if os(Windows)
        try run("tar", ["-xf", archive.path, "-C", contents.path])
        #else
        try run("unzip", ["-q", archive.path, "-d", contents.path])
        #endif
        try FileManager.default.removeItem(at: archive)
        return usage(contents)
    }
}
