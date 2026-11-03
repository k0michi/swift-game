#if !os(Windows)
    import Foundation

    // How macOS and Linux name and find executables and libraries.

    /// The directories on the PATH.
    var searchPath: [String] {
        (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
    }

    /// The names an executable called `name` can have.
    func executableNames(_ name: String) -> [String] {
        [name]
    }

    /// `name` as an executable is named.
    func executableName(_ name: String) -> String {
        name
    }

    /// The file of a static library called `name`, which `-l<name>` links.
    func staticLibraryName(_ name: String) -> String {
        "lib\(name).a"
    }
#endif
