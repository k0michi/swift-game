#if !os(Linux)
    import Foundation

    // macOS and Windows start commands with Foundation's Process.

    func spawn(
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
