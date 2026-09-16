import CSDL3

// SDL_MAJOR_VERSION
public let majorVersion = Int32(SDL_MAJOR_VERSION)

// SDL_MINOR_VERSION
public let minorVersion = Int32(SDL_MINOR_VERSION)

// SDL_MICRO_VERSION
public let microVersion = Int32(SDL_MICRO_VERSION)

// SDL_VERSIONNUM
public struct Version: RawRepresentable, Comparable, Hashable, Sendable {
    public let rawValue: Int32

    // SDL_VERSIONNUM
    public init(major: Int32, minor: Int32, patch: Int32) {
        rawValue = major * 1_000_000 + minor * 1_000 + patch
    }

    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    // SDL_VERSIONNUM_MAJOR
    public var major: Int32 {
        rawValue / 1_000_000
    }

    // SDL_VERSIONNUM_MINOR
    public var minor: Int32 {
        rawValue / 1_000 % 1_000
    }

    // SDL_VERSIONNUM_MICRO
    public var micro: Int32 {
        rawValue % 1_000
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// SDL_VERSION
public let version = Version(
    major: majorVersion,
    minor: minorVersion,
    patch: microVersion
)

// SDL_VERSION_ATLEAST
public func versionAtLeast(
    major: Int32,
    minor: Int32,
    patch: Int32
) -> Bool {
    version >= Version(major: major, minor: minor, patch: patch)
}

// SDL_GetVersion
public func getVersion() -> Version {
    Version(rawValue: SDL_GetVersion())
}

// SDL_GetRevision
public func getRevision() -> String {
    String(cString: SDL_GetRevision())
}
