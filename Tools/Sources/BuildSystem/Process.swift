import Foundation

public struct ProcessError: Error, CustomStringConvertible {
    public let command: [String]
    public let status: Int32

    public var description: String {
        "\(command.joined(separator: " ")) exited with status \(status)"
    }
}

// Runs a command, with its output going to this process's, and throws if it
// fails. The executable is looked up in PATH unless it is a path.
public func run(
    _ executable: String,
    _ arguments: [String],
    in directory: URL? = nil,
    environment: [String: String] = [:]
) throws {
    let process = try makeProcess(executable, arguments, in: directory, environment: environment)
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw ProcessError(command: [executable] + arguments, status: process.terminationStatus)
    }
}

// Runs a command and returns its standard output without the trailing newline.
public func output(
    _ executable: String,
    _ arguments: [String],
    in directory: URL? = nil,
    environment: [String: String] = [:]
) throws -> String {
    let process = try makeProcess(executable, arguments, in: directory, environment: environment)
    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw ProcessError(command: [executable] + arguments, status: process.terminationStatus)
    }
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines)
}

// The full path of an executable in PATH.
public func which(_ name: String) throws -> URL {
    if name.contains("/") || name.contains("\\") { return URL(fileURLWithPath: name) }
    #if os(Windows)
    let environment = ProcessInfo.processInfo.environment
    let paths = (environment["Path"] ?? environment["PATH"] ?? "").split(separator: ";")
    let names = [name] + (environment["PATHEXT"] ?? ".EXE;.CMD;.BAT").split(separator: ";").map { name + $0 }
    #else
    let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
    let names = [name]
    #endif
    for path in paths {
        for name in names {
            let candidate = URL(fileURLWithPath: String(path)).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate.resolvingSymlinksInPath()
            }
        }
    }
    throw BuildError("\(name) is not in PATH")
}

private func makeProcess(
    _ executable: String,
    _ arguments: [String],
    in directory: URL?,
    environment: [String: String]
) throws -> Process {
    let process = Process()
    process.executableURL = try which(executable)
    process.arguments = arguments
    if let directory { process.currentDirectoryURL = directory }
    if !environment.isEmpty {
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
    }
    return process
}

public struct BuildError: Error, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}
