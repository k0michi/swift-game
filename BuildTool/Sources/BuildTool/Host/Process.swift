import Foundation

// What every host runs commands with. How a host finds and starts them is in
// the host's own files, beside this one.

struct BuildToolError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

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
    let status = try spawn(command, in: directory, environment: environment, capturingOutput: false).status
    guard status == 0 else {
        throw CommandError(command: command, status: status)
    }
}

/// Runs `command` and returns what it writes to its standard output, without
/// what it writes to its standard error, such as swift-driver's version, which
/// swiftc --version writes there.
func output(of command: [String], in directory: URL? = nil) throws -> String {
    let (status, output) = try spawn(command, in: directory, environment: [:], capturingOutput: true)
    guard status == 0 else {
        throw CommandError(command: command, status: status)
    }
    return String(decoding: output, as: UTF8.self)
}

/// The executable `name` on the PATH, or at its path if it has one.
func executable(named name: String) throws -> URL {
    if name.contains("/") || name.contains("\\") {
        return URL(fileURLWithPath: name)
    }
    for directory in searchPath {
        for name in executableNames(name) {
            // Not a directory, such as Emscripten's cmake beside its emcmake.
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), !isDirectory.boolValue,
                FileManager.default.isExecutableFile(atPath: candidate.path)
            {
                return candidate
            }
        }
    }
    throw BuildToolError("\(name) is not on the PATH")
}

/// Whether `path` is absolute, on POSIX or, with a drive letter, on Windows,
/// as CMake writes paths on either.
func isAbsolutePath(_ path: String) -> Bool {
    if path.hasPrefix("/") {
        return true
    }
    let characters = Array(path)
    return characters.count > 2 && characters[0].isLetter && characters[1] == ":"
        && (characters[2] == "/" || characters[2] == "\\")
}
