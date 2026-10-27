import Foundation

// Where a project's sources, artifacts and pkg-config files go, all under
// its .build directory.
public struct Workspace: Sendable {
    public let root: URL
    // A directory with clones of the Git sources, named as the last path
    // component of their URLs, to fetch from instead of the network.
    public let sourceMirror: URL?

    public init(root: URL, sourceMirror: URL? = nil) {
        self.root = root
        self.sourceMirror = sourceMirror
    }

    public var buildDirectory: URL { root.appendingPathComponent(".build") }

    public var sourcesDirectory: URL { buildDirectory.appendingPathComponent("sources") }

    public func artifactsDirectory(for platform: Platform) -> URL {
        buildDirectory.appendingPathComponent("artifacts").appendingPathComponent(platform.rawValue)
    }

    // The directory SwiftPM reads .pc files from for a platform.
    public func pkgConfigDirectory(for platform: Platform) -> URL {
        artifactsDirectory(for: platform).appendingPathComponent("pkgconfig")
    }
}
