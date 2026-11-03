import Foundation

/// A project to build: what it fetches and builds with CMake, the files it
/// downloads, and the Swift targets that SwiftPM builds from them.
///
/// Build.swift makes one, as Package.swift makes a `Package`, and BuildTool
/// runs Build.swift to read it.
public struct Build: Codable, Sendable {
    public var name: String
    /// The oldest macOS the targets and the CMake projects build for.
    public var macOSDeploymentTarget: String?
    public var cmakeProjects: [CMakeProject]
    public var downloads: [Download]
    public var targets: [Target]

    public init(
        name: String,
        macOSDeploymentTarget: String? = nil,
        cmakeProjects: [CMakeProject] = [],
        downloads: [Download] = [],
        targets: [Target]
    ) {
        self.name = name
        self.macOSDeploymentTarget = macOSDeploymentTarget
        self.cmakeProjects = cmakeProjects
        self.downloads = downloads
        self.targets = targets
        Self.write(self)
    }

    // BuildTool names the file in the environment to write the description
    // to, as JSON.
    static let outputVariable = "BUILDTOOL_DESCRIPTION_OUTPUT"

    private static func write(_ build: Build) {
        guard let path = ProcessInfo.processInfo.environment[outputVariable] else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(build).write(to: URL(fileURLWithPath: path))
        } catch {
            FileHandle.standardError.write(Data("Could not write the description: \(error)\n".utf8))
            exit(1)
        }
    }
}

/// A CMake project at a git revision, configured with `options`, of which
/// `targets` are built.
public struct CMakeProject: Codable, Sendable {
    public var name: String
    public var git: String
    public var revision: String
    public var options: [String: String]
    public var targets: [String]

    public init(_ name: String, git: String, revision: String, options: [String: String] = [:], targets: [String]) {
        self.name = name
        self.git = git
        self.revision = revision
        self.options = options
        self.targets = targets
    }

    /// One of its targets, for a C target to link.
    public func target(_ name: String) -> CMakeTarget {
        CMakeTarget(project: self.name, target: name)
    }
}

public struct CMakeTarget: Codable, Sendable, Hashable {
    public var project: String
    public var target: String
}

/// A file downloaded from `url` and checked against its SHA-256, saved as
/// `name`.
public struct Download: Codable, Sendable {
    public var name: String
    public var url: String
    public var sha256: String

    public init(_ name: String, url: String, sha256: String) {
        self.name = name
        self.url = url
        self.sha256 = sha256
    }
}

/// A SwiftPM target, with what BuildTool adds to it: the CMake targets it
/// links, whose headers it and the targets depending on it see, and, for an
/// executable, the downloads put beside it.
public struct Target: Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case regular, executable, test
    }

    public var name: String
    public var kind: Kind
    public var dependencies: [String]
    public var path: String?
    public var linking: [CMakeTarget]
    /// The name of the executable's product.
    public var product: String?
    public var assets: [String]

    public static func target(
        name: String, dependencies: [String] = [], path: String? = nil, linking: [CMakeTarget] = []
    ) -> Target {
        Target(name: name, kind: .regular, dependencies: dependencies, path: path, linking: linking, assets: [])
    }

    public static func executableTarget(
        name: String, product: String? = nil, dependencies: [String] = [], path: String? = nil,
        linking: [CMakeTarget] = [], assets: [Download] = []
    ) -> Target {
        Target(
            name: name, kind: .executable, dependencies: dependencies, path: path, linking: linking,
            product: product ?? name, assets: assets.map(\.name))
    }

    public static func testTarget(name: String, dependencies: [String] = [], path: String? = nil) -> Target {
        Target(name: name, kind: .test, dependencies: dependencies, path: path, linking: [], assets: [])
    }
}
