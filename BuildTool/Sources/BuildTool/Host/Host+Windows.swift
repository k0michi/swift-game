#if os(Windows)
    import Foundation

    // How Windows names and finds executables.

    /// The directories on the PATH, which Windows names Path and separates
    /// with semicolons.
    var searchPath: [String] {
        let path = ProcessInfo.processInfo.environment.first { $0.key.uppercased() == "PATH" }?.value ?? ""
        return path.split(separator: ";").map(String.init)
    }

    /// The names an executable called `name` can have.
    func executableNames(_ name: String) -> [String] {
        name.hasSuffix(".exe") ? [name] : [name + ".exe", name]
    }

    /// `name` as an executable is named.
    func executableName(_ name: String) -> String {
        name + ".exe"
    }
#endif
