import CBuildInfo

/// What was built, which the build scripts embed.
enum BuildInfo {
    /// `git describe` of the source: the last tag, the commits since and the
    /// commit, or the commit alone with no tag, and `-dirty` if files changed.
    static let version = String(cString: build_info_version())
}
