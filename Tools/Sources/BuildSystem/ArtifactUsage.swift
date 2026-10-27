import Foundation

// What compiling against and linking with an artifact takes.
public struct ArtifactUsage: Codable, Sendable {
    public var includeDirectories: [String] = []
    public var frameworkDirectories: [String] = []
    public var libraryDirectories: [String] = []
    public var libraries: [String] = []
    public var frameworks: [String] = []
    // Preprocessor definitions and linker flags that pkg-config files cannot
    // carry into SwiftPM, for the build commands to pass themselves.
    public var defines: [String] = []
    public var linkerFlags: [String] = []

    public init() {}

    // A .pc file with what SwiftPM accepts from one: -I and -F for
    // compiling, -L, -l, -F and -framework for linking.
    public func pkgConfig(name: String) -> String {
        let cflags = includeDirectories.map { "-I" + escaped($0) } + frameworkDirectories.map { "-F" + escaped($0) }
        let libs = libraryDirectories.map { "-L" + escaped($0) }
            + frameworkDirectories.map { "-F" + escaped($0) }
            + libraries.map { "-l" + $0 }
            + frameworks.flatMap { ["-framework", $0] }
        return """
            Name: \(name)
            Description: \(name), built for swift-game
            Version: 0
            Cflags: \(cflags.joined(separator: " "))
            Libs: \(libs.joined(separator: " "))

            """
    }

    mutating func append(_ other: ArtifactUsage) {
        func merge(_ path: WritableKeyPath<ArtifactUsage, [String]>) {
            for value in other[keyPath: path] where !self[keyPath: path].contains(value) {
                self[keyPath: path].append(value)
            }
        }
        merge(\.includeDirectories)
        merge(\.frameworkDirectories)
        merge(\.libraryDirectories)
        merge(\.libraries)
        merge(\.frameworks)
        merge(\.defines)
        merge(\.linkerFlags)
    }
}

private func escaped(_ path: String) -> String {
    path.replacingOccurrences(of: " ", with: "\\ ")
}
