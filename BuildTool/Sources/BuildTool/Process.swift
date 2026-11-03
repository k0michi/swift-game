import Foundation

struct CommandError: Error, CustomStringConvertible {
    let command: [String]
    let status: Int32

    var description: String {
        "\(command.joined(separator: " ")) exited with \(status)"
    }
}

/// Runs `command`, found on the PATH, with its output going where BuildTool's
/// does.
func run(_ command: [String], in directory: URL? = nil, environment: [String: String] = [:]) throws {
    let process = try makeProcess(command, in: directory, environment: environment)
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw CommandError(command: command, status: process.terminationStatus)
    }
}

/// Runs `command` and returns what it writes to its standard output.
func output(of command: [String], in directory: URL? = nil) throws -> String {
    let process = try makeProcess(command, in: directory, environment: [:])
    let pipe = Pipe()
    process.standardOutput = pipe
    // Such as swift-driver's version, which swiftc --version writes there.
    process.standardError = FileHandle.nullDevice
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw CommandError(command: command, status: process.terminationStatus)
    }
    return String(decoding: data, as: UTF8.self)
}

private func makeProcess(_ command: [String], in directory: URL?, environment: [String: String]) throws -> Process {
    let process = Process()
    process.executableURL = try executable(named: command[0])
    process.arguments = Array(command.dropFirst())
    process.currentDirectoryURL = directory
    process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
    return process
}

/// The executable `name`, as the shell would find it on the PATH, or at its
/// path if it has one.
func executable(named name: String) throws -> URL {
    if name.contains("/") {
        return URL(fileURLWithPath: name)
    }
    let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
    for directory in path.split(separator: ":") {
        let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(name)
        if FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
    }
    throw BuildToolError("\(name) is not on the PATH")
}

struct BuildToolError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
