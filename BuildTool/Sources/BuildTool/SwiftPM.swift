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

    /// Where swift build puts what it builds: the last line it writes, which
    /// ends in CR LF on Windows.
    func binPath() throws -> URL {
        let path = try output(of: command("build", ["--show-bin-path"]))
            .split(whereSeparator: \.isNewline).last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return URL(fileURLWithPath: path)
    }
}
