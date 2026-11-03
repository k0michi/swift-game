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
    public var dependencies: [PackageDependency]
    public var products: [Product]
    public var targets: [Target]
    /// The environment `buildtool test` runs the tests in.
    public var testEnvironment: [String: String]

    public init(
        name: String,
        macOSDeploymentTarget: String? = nil,
        cmakeProjects: [CMakeProject] = [],
        downloads: [Download] = [],
        dependencies: [PackageDependency] = [],
        products: [Product] = [],
        targets: [Target],
        testEnvironment: [String: String] = [:]
    ) {
        self.name = name
        self.macOSDeploymentTarget = macOSDeploymentTarget
        self.cmakeProjects = cmakeProjects
        self.downloads = downloads
        self.dependencies = dependencies
        self.products = products
        self.targets = targets
        self.testEnvironment = testEnvironment
        Self.write(self)
    }

    // BuildTool names the file in the environment to write the description
    // to, as JSON.
    static let outputVariable = "BUILDTOOL_DESCRIPTION_OUTPUT"

    private static func write(_ build: Build) {
        guard let path = ProcessInfo.processInfo.environment[outputVariable] else { return }
        // BuildTool removes the file before running Build.swift.
        guard !FileManager.default.fileExists(atPath: path) else {
            FileHandle.standardError.write(Data("Build.swift declares more than one Build\n".utf8))
            exit(1)
        }
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

/// A CMake project, configured with `options`, of which `targets` are built.
///
/// What the targets give what links them, their include directories and the
/// libraries they need, BuildTool reads from CMake. What CMake does not know,
/// such as the C++ library a C++ target needs on Linux, is declared in
/// `includeDirectories` and `linkerFlags`, which go to every target linking
/// one of the project's.
public struct CMakeProject: Codable, Sendable {
    public enum Source: Codable, Sendable {
        /// A revision of a git repository.
        case git(url: String, revision: String)
        /// A directory, relative to the project's.
        case path(String)
    }

    public var name: String
    public var source: Source
    public var options: [String: String]
    public var targets: [String]
    public var includeDirectories: [String]
    public var linkerFlags: [String]

    /// A project at a git revision.
    public init(
        _ name: String, git: String, revision: String, options: [String: String] = [:], targets: [String],
        includeDirectories: [String] = [], linkerFlags: [String] = []
    ) {
        self.init(
            name, source: .git(url: git, revision: revision), options: options, targets: targets,
            includeDirectories: includeDirectories, linkerFlags: linkerFlags)
    }

    /// A project in a directory, relative to the project's, such as a
    /// CMakeLists.txt written for sources without a CMake project of their own.
    public init(
        _ name: String, path: String, options: [String: String] = [:], targets: [String],
        includeDirectories: [String] = [], linkerFlags: [String] = []
    ) {
        self.init(
            name, source: .path(path), options: options, targets: targets, includeDirectories: includeDirectories,
            linkerFlags: linkerFlags)
    }

    public init(
        _ name: String, source: Source, options: [String: String], targets: [String], includeDirectories: [String],
        linkerFlags: [String]
    ) {
        self.name = name
        self.source = source
        self.options = options
        self.targets = targets
        self.includeDirectories = includeDirectories
        self.linkerFlags = linkerFlags
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

/// A package that the targets' products come from, as
/// `.package(url:from:)`.
public struct PackageDependency: Codable, Sendable {
    public var url: String
    public var from: String

    public static func package(url: String, from: String) -> PackageDependency {
        PackageDependency(url: url, from: from)
    }
}

/// A library product, besides the executables' products.
public struct Product: Codable, Sendable {
    public var name: String
    public var targets: [String]

    public static func library(name: String, targets: [String]) -> Product {
        Product(name: name, targets: targets)
    }
}

/// What a target depends on: another target, by its name, or a product of a
/// package dependency.
public enum Dependency: Codable, Sendable, ExpressibleByStringLiteral {
    case target(String)
    case product(name: String, package: String)

    public init(stringLiteral name: String) {
        self = .target(name)
    }
}

/// A resource of a target, as SwiftPM copies or processes it.
public enum Resource: Codable, Sendable {
    case copy(String)
    case process(String)
}

/// A SwiftPM target, with what BuildTool adds to it: the CMake targets it
/// links, whose headers it and the targets depending on it see, and, for an
/// executable, the downloads put beside it. Its own flags are SwiftPM's
/// unsafe flags.
public struct Target: Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case regular, executable, test
    }

    public var name: String
    public var kind: Kind
    public var dependencies: [Dependency]
    public var path: String?
    public var exclude: [String]
    public var resources: [Resource]
    public var cFlags: [String]
    public var swiftFlags: [String]
    public var linkerFlags: [String]
    public var linking: [CMakeTarget]
    /// The name of the executable's product.
    public var product: String?
    public var assets: [String]

    public static func target(
        name: String, dependencies: [Dependency] = [], path: String? = nil, exclude: [String] = [],
        resources: [Resource] = [], cFlags: [String] = [], swiftFlags: [String] = [], linkerFlags: [String] = [],
        linking: [CMakeTarget] = []
    ) -> Target {
        Target(
            name: name, kind: .regular, dependencies: dependencies, path: path, exclude: exclude,
            resources: resources, cFlags: cFlags, swiftFlags: swiftFlags, linkerFlags: linkerFlags, linking: linking,
            assets: [])
    }

    public static func executableTarget(
        name: String, product: String? = nil, dependencies: [Dependency] = [], path: String? = nil,
        exclude: [String] = [], resources: [Resource] = [], cFlags: [String] = [], swiftFlags: [String] = [],
        linkerFlags: [String] = [], linking: [CMakeTarget] = [], assets: [Download] = []
    ) -> Target {
        Target(
            name: name, kind: .executable, dependencies: dependencies, path: path, exclude: exclude,
            resources: resources, cFlags: cFlags, swiftFlags: swiftFlags, linkerFlags: linkerFlags, linking: linking,
            product: product ?? name, assets: assets.map(\.name))
    }

    public static func testTarget(
        name: String, dependencies: [Dependency] = [], path: String? = nil, exclude: [String] = [],
        resources: [Resource] = [], cFlags: [String] = [], swiftFlags: [String] = [], linkerFlags: [String] = []
    ) -> Target {
        Target(
            name: name, kind: .test, dependencies: dependencies, path: path, exclude: exclude, resources: resources,
            cFlags: cFlags, swiftFlags: swiftFlags, linkerFlags: linkerFlags, linking: [], assets: [])
    }
}
