import CHarfBuzz

// hb_version
public func version() -> (major: UInt32, minor: UInt32, micro: UInt32) {
    var major: UInt32 = 0
    var minor: UInt32 = 0
    var micro: UInt32 = 0
    hb_version(&major, &minor, &micro)
    return (major, minor, micro)
}

// hb_version_string
public func versionString() -> String {
    String(cString: hb_version_string())
}
