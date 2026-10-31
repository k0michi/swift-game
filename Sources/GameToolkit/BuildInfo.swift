import CBuildInfo

/// What was built, which the build scripts embed.
public enum BuildInfo {
    /// `git describe` of the source: the last tag, the commits since and the
    /// commit, or the commit alone with no tag, and `-dirty` if files changed.
    public static let version = String(cString: build_info_version())

    /// The version of the Swift compiler that built it, such as "6.3.1".
    public static let swiftVersion = String(cString: build_info_swift_version())

    /// The target triple without an OS version, such as
    /// "arm64-apple-macosx" or "wasm32-unknown-emscripten".
    public static let triple = String(cString: build_info_triple())

    /// "debug" or "release", as SwiftPM built it.
    public static let configuration: String = {
        #if DEBUG
            "debug"
        #else
            "release"
        #endif
    }()
}
