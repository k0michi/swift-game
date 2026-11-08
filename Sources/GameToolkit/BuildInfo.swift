import CBuildInfo

/// What was built, which the build scripts embed.
public enum BuildInfo {
    /// `git describe` of the source: the last tag, the commits since and the
    /// commit, or the commit alone with no tag, and `-dirty` if files changed.
    public static let version = String(cString: build_info_version())

    /// The version of the Swift compiler that built it, such as "6.3.1".
    public static let swiftVersion = String(cString: build_info_swift_version())

    /// The operating system and the architecture it was built for, such as
    /// "macOS arm64" or "Emscripten wasm32".
    public static let platform: String = {
        let system: String = {
            #if os(macOS)
                "macOS"
            #elseif os(iOS)
                "iOS"
            #elseif os(Windows)
                "Windows"
            #elseif os(Linux)
                "Linux"
            #elseif os(Emscripten)
                "Emscripten"
            #else
                "unknown"
            #endif
        }()
        let architecture: String = {
            #if arch(arm64)
                "arm64"
            #elseif arch(x86_64)
                "x86_64"
            #elseif arch(wasm32)
                "wasm32"
            #else
                "unknown"
            #endif
        }()
        return "\(system) \(architecture)"
    }()

    /// "debug" or "release", as SwiftPM built it.
    public static let configuration: String = {
        #if DEBUG
            "debug"
        #else
            "release"
        #endif
    }()
}
