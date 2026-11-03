import CFreeType

// FT_Library
public final class Library {
    let pointer: FT_Library

    fileprivate init(pointer: FT_Library) {
        self.pointer = pointer
    }

    deinit {
        FT_Done_FreeType(pointer)
    }
}

// FT_Init_FreeType
public func initFreeType() throws -> Library {
    var library: FT_Library?
    try check("FT_Init_FreeType", FT_Init_FreeType(&library))
    return Library(pointer: library!)
}

// FT_Library_Version
public func libraryVersion(library: Library) -> (major: Int32, minor: Int32, patch: Int32) {
    var major: FT_Int = 0
    var minor: FT_Int = 0
    var patch: FT_Int = 0
    FT_Library_Version(library.pointer, &major, &minor, &patch)
    return (major, minor, patch)
}
