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

#if os(Linux)
    import Glibc

    // posix_spawn and waitpid, as Foundation's Process can wait for ever for a
    // child that has exited, as it does in a container started by
    // `docker run ... sleep infinity`.
    private func spawn(
        _ command: [String], in directory: URL?, environment: [String: String], capturingOutput: Bool
    ) throws -> (status: Int32, output: Data) {
        let path = try executable(named: command[0]).path
        var actions = posix_spawn_file_actions_t()
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        if let directory {
            posix_spawn_file_actions_addchdir_np(&actions, directory.path)
        }
        var pipe: [Int32] = [-1, -1]
        if capturingOutput {
            guard Glibc.pipe(&pipe) == 0 else { throw BuildToolError("Could not make a pipe") }
            posix_spawn_file_actions_adddup2(&actions, pipe[1], 1)
            posix_spawn_file_actions_addclose(&actions, pipe[0])
            posix_spawn_file_actions_addclose(&actions, pipe[1])
            posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)
        }

        let arguments = command.map { strdup($0) } + [nil]
        let variables = ProcessInfo.processInfo.environment.merging(environment) { $1 }.map { strdup("\($0)=\($1)") }
            + [nil]
        defer {
            arguments.forEach { free($0) }
            variables.forEach { free($0) }
        }
        var pid: pid_t = 0
        let error = posix_spawn(&pid, path, &actions, nil, arguments, variables)
        if capturingOutput {
            close(pipe[1])
        }
        guard error == 0 else {
            if capturingOutput { close(pipe[0]) }
            throw BuildToolError("Could not run \(path): \(String(cString: strerror(error)))")
        }

        var output = Data()
        if capturingOutput {
            var buffer = [UInt8](repeating: 0, count: 65536)
            while true {
                let count = read(pipe[0], &buffer, buffer.count)
                if count > 0 {
                    output.append(contentsOf: buffer[..<count])
                } else if count == 0 || errno != EINTR {
                    break
                }
            }
            close(pipe[0])
        }

        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 {
            guard errno == EINTR else { throw BuildToolError("Could not wait for \(path)") }
        }
        // WIFEXITED and WEXITSTATUS, or 128 and the signal that ended it.
        let signal = status & 0x7f
        return (signal == 0 ? (status >> 8) & 0xff : 128 + signal, output)
    }
#else
    private func spawn(
        _ command: [String], in directory: URL?, environment: [String: String], capturingOutput: Bool
    ) throws -> (status: Int32, output: Data) {
        let process = Process()
        process.executableURL = try executable(named: command[0])
        process.arguments = Array(command.dropFirst())
        process.currentDirectoryURL = directory
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        var output = Data()
        if capturingOutput {
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try process.run()
            output = pipe.fileHandleForReading.readDataToEndOfFile()
        } else {
            try process.run()
        }
        process.waitUntilExit()
        return (process.terminationStatus, output)
    }
#endif

/// The executable `name`, as the shell would find it on the PATH, or at its
/// path if it has one. On Windows it is found with its `.exe`.
func executable(named name: String) throws -> URL {
    if name.contains("/") || name.contains("\\") {
        return URL(fileURLWithPath: name)
    }
    #if os(Windows)
        // Windows names it Path, and its parts are apart by semicolons.
        let path = ProcessInfo.processInfo.environment.first { $0.key.uppercased() == "PATH" }?.value ?? ""
        let directories = path.split(separator: ";")
        let names = name.hasSuffix(".exe") ? [name] : [name + ".exe", name]
    #else
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let directories = path.split(separator: ":")
        let names = [name]
    #endif
    for directory in directories {
        for name in names {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
    }
    throw BuildToolError("\(name) is not on the PATH")
}

/// `name` as an executable is named on the platform BuildTool runs on.
func executableName(_ name: String) -> String {
    #if os(Windows)
        name + ".exe"
    #else
        name
    #endif
}

/// Whether `path` is absolute, with a drive letter on Windows.
func isAbsolutePath(_ path: String) -> Bool {
    if path.hasPrefix("/") {
        return true
    }
    let characters = Array(path)
    return characters.count > 2 && characters[0].isLetter && characters[1] == ":"
        && (characters[2] == "/" || characters[2] == "\\")
}

struct BuildToolError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
