import Foundation

/// swift build and swift test on the project, for a platform, with the
/// arguments buildtool was given for them.
struct SwiftPM {
    let project: URL
    let platform: any TargetPlatform
    let arguments: [String]

    /// The `subcommand` with the platform's arguments, `extra`, and the given
    /// ones.
    func command(_ subcommand: String, _ extra: [String] = []) -> [String] {
        ["swift", subcommand, "--package-path", project.path] + platform.swiftArguments + extra + arguments
    }

    /// Where swift build puts what it builds.
    func binPath() throws -> URL {
        let path = try output(of: command("build", ["--show-bin-path"]))
            .split(separator: "\n").last.map(String.init) ?? ""
        return URL(fileURLWithPath: path)
    }
}
