import BuildDescription
import Foundation

/// buildtool's options, its command, and the arguments after it.
struct Options {
    var project = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    var platform = Platform.host
    var swiftSDK: String?
    var command = "build"
    var arguments: [String] = []

    init(_ arguments: [String]) throws {
        var arguments = arguments
        while let option = arguments.first, option.hasPrefix("--"), arguments.count > 1 {
            let value = arguments[1]
            switch option {
            case "--project-path": project = URL(fileURLWithPath: value).standardizedFileURL
            case "--platform":
                guard let platform = Platform(rawValue: value) else {
                    throw BuildToolError("Unknown platform \(value)")
                }
                self.platform = platform
            case "--swift-sdk": swiftSDK = value
            default: throw BuildToolError("Unknown option \(option)")
            }
            arguments.removeFirst(2)
        }
        command = arguments.first ?? "build"
        self.arguments = Array(arguments.dropFirst())
    }
}
