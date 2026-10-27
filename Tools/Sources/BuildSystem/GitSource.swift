import Foundation

// A Git repository at a fixed commit, with patches applied.
public struct GitSource: Sendable, CustomStringConvertible {
    public let url: String
    public let commit: String
    public let patches: [URL]

    public init(_ url: String, commit: String, patches: [URL] = []) {
        self.url = url
        self.commit = commit
        self.patches = patches
    }

    public var name: String {
        var name = url.split(separator: "/").last.map(String.init) ?? url
        if name.hasSuffix(".git") { name.removeLast(4) }
        return name
    }

    public var description: String {
        ([url, commit] + patches.map { (try? String(contentsOf: $0, encoding: .utf8)) ?? $0.path })
            .joined(separator: "\n")
    }

    // Checks the commit out into workspace.sourcesDirectory/<name> unless it
    // is there already, and returns that directory.
    @discardableResult
    public func checkout(in workspace: Workspace) throws -> URL {
        let directory = workspace.sourcesDirectory.appendingPathComponent(name)
        let stamp = directory.appendingPathComponent(".git/swift-game-source")
        if (try? String(contentsOf: stamp, encoding: .utf8)) == description {
            return directory
        }

        let remote = workspace.sourceMirror?.appendingPathComponent(name).path ?? url
        print("Fetching \(name) at \(commit.prefix(12))")
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try run("git", ["init", "--quiet"], in: directory)
        try run("git", ["fetch", "--quiet", "--depth", "1", remote, commit], in: directory)
        try run("git", ["checkout", "--quiet", "FETCH_HEAD"], in: directory)
        for patch in patches {
            try run("git", ["apply", patch.path], in: directory)
        }
        try description.write(to: stamp, atomically: true, encoding: .utf8)
        return directory
    }
}
