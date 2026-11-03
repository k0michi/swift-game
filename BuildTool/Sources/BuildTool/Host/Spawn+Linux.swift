#if os(Linux)
    import Foundation
    import Glibc

    // Linux starts commands with posix_spawn and waits with waitpid, as
    // Foundation's Process can wait for ever for a child that has exited, as
    // it does in a container started by `docker run ... sleep infinity`.

    func spawn(
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
#endif
