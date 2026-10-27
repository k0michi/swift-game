import Foundation

// A CMake project built from source. Its usage is read from a probe: a
// generated project that adds the source as a subdirectory and links an
// executable with `targets`, so that CMake resolves their include
// directories and link libraries, which the File API then reports.
public struct CMakeArtifact: Artifact {
    public let name: String
    public let source: GitSource
    // Cache variables set when configuring, such as options of the project.
    public let cacheVariables: [String: String]
    // The targets to link with, as `target_link_libraries` takes them.
    public let targets: [String]
    public let languages: [String]
    public let platforms: Set<Platform>

    public init(
        _ name: String,
        source: GitSource,
        cacheVariables: [String: String] = [:],
        targets: [String],
        languages: [String] = ["C"],
        platforms: Set<Platform> = Set(Platform.allCases)
    ) {
        self.name = name
        self.source = source
        self.cacheVariables = cacheVariables
        self.targets = targets
        self.languages = languages
        self.platforms = platforms
    }

    public var fingerprint: String {
        ([source.description] + cacheVariables.sorted { $0.key < $1.key }.map { "\($0)=\($1)" } + targets + languages)
            .joined(separator: "\n")
    }

    public func build(for toolchain: Toolchain, into directory: URL, in workspace: Workspace) throws -> ArtifactUsage {
        let sourceDirectory = try source.checkout(in: workspace)
        let probeDirectory = directory.appendingPathComponent("probe")
        let buildDirectory = directory.appendingPathComponent("build")
        try FileManager.default.createDirectory(at: probeDirectory, withIntermediateDirectories: true)
        try """
            cmake_minimum_required(VERSION 3.24)
            project(\(name)Probe LANGUAGES \(languages.joined(separator: " ")))
            add_subdirectory("\(cmakeEscaped(sourceDirectory.path))" "${CMAKE_BINARY_DIR}/\(name)" EXCLUDE_FROM_ALL)
            add_executable(probe probe.c)
            target_link_libraries(probe PRIVATE \(targets.joined(separator: " ")))

            """.write(to: probeDirectory.appendingPathComponent("CMakeLists.txt"), atomically: true, encoding: .utf8)
        try "int main(void) { return 0; }\n"
            .write(to: probeDirectory.appendingPathComponent("probe.c"), atomically: true, encoding: .utf8)

        let fileAPI = CMakeFileAPI(buildDirectory: buildDirectory)
        try fileAPI.writeQuery()
        try run("cmake", [
            "-G", "Ninja",
            "-S", probeDirectory.path,
            "-B", buildDirectory.path,
            "-DCMAKE_BUILD_TYPE=Release",
        ] + toolchain.cmakeArguments + cacheVariables.sorted { $0.key < $1.key }.map { "-D\($0)=\($1)" })
        try run("cmake", ["--build", buildDirectory.path, "--target", "probe", "--parallel"])
        return try fileAPI.usage(of: "probe", platform: toolchain.platform)
    }
}

private func cmakeEscaped(_ string: String) -> String {
    string.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
}
