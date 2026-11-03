import CFreeType

// FT_Face with the font file it reads, which FT_New_Memory_Face does not copy,
// and the library it belongs to, so both live as long as it.
public final class Face {
    let pointer: FT_Face
    private let library: Library
    private let data: UnsafeMutableBufferPointer<UInt8>

    fileprivate init(pointer: FT_Face, library: Library, data: UnsafeMutableBufferPointer<UInt8>) {
        self.pointer = pointer
        self.library = library
        self.data = data
    }

    deinit {
        FT_Done_Face(pointer)
        data.deallocate()
    }

    // FT_FaceRec.num_faces
    public var numFaces: Int { Int(pointer.pointee.num_faces) }
    // FT_FaceRec.num_glyphs
    public var numGlyphs: Int { Int(pointer.pointee.num_glyphs) }
    // FT_FaceRec.family_name
    public var familyName: String? { pointer.pointee.family_name.map { String(cString: $0) } }
    // FT_FaceRec.style_name
    public var styleName: String? { pointer.pointee.style_name.map { String(cString: $0) } }
    // FT_FaceRec.units_per_EM
    public var unitsPerEM: UInt16 { pointer.pointee.units_per_EM }
    // FT_FaceRec.ascender
    public var ascender: Int16 { pointer.pointee.ascender }
    // FT_FaceRec.descender
    public var descender: Int16 { pointer.pointee.descender }
    // FT_FaceRec.height
    public var height: Int16 { pointer.pointee.height }
    // FT_FaceRec.glyph
    public var glyph: GlyphSlot { GlyphSlot(face: self) }
    // FT_FaceRec.size
    public var size: Size { Size(metrics: SizeMetrics(pointer.pointee.size.pointee.metrics)) }
}

// FT_SizeRec
public struct Size: Equatable, Sendable {
    public var metrics: SizeMetrics
}

// FT_Size_Metrics, in 26.6 fixed point but the scales, which are 16.16.
public struct SizeMetrics: Equatable, Sendable {
    public var xPpem: UInt16
    public var yPpem: UInt16
    public var xScale: Int
    public var yScale: Int
    public var ascender: Int
    public var descender: Int
    public var height: Int
    public var maxAdvance: Int

    init(_ metrics: FT_Size_Metrics) {
        xPpem = metrics.x_ppem
        yPpem = metrics.y_ppem
        xScale = Int(metrics.x_scale)
        yScale = Int(metrics.y_scale)
        ascender = Int(metrics.ascender)
        descender = Int(metrics.descender)
        height = Int(metrics.height)
        maxAdvance = Int(metrics.max_advance)
    }
}

// FT_Kerning_Mode
public enum KerningMode: UInt32, Sendable {
    case `default` = 0
    case unfitted = 1
    case unscaled = 2
}

// FT_New_Memory_Face
public func newMemoryFace(library: Library, fileBase: [UInt8], faceIndex: Int = 0) throws -> Face {
    let copy = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: max(fileBase.count, 1))
    _ = copy.initialize(from: fileBase)
    var face: FT_Face?
    let error = FT_New_Memory_Face(library.pointer, copy.baseAddress, FT_Long(fileBase.count), FT_Long(faceIndex), &face)
    guard error == 0, let face else {
        copy.deallocate()
        throw FreeTypeError(operation: "FT_New_Memory_Face", code: error)
    }
    return Face(pointer: face, library: library, data: copy)
}

// FT_Set_Pixel_Sizes
public func setPixelSizes(face: Face, pixelWidth: UInt32, pixelHeight: UInt32) throws {
    try check("FT_Set_Pixel_Sizes", FT_Set_Pixel_Sizes(face.pointer, pixelWidth, pixelHeight))
}

// FT_Set_Char_Size
public func setCharSize(
    face: Face, charWidth: Int, charHeight: Int, horzResolution: UInt32 = 0, vertResolution: UInt32 = 0
) throws {
    try check(
        "FT_Set_Char_Size",
        FT_Set_Char_Size(face.pointer, FT_F26Dot6(charWidth), FT_F26Dot6(charHeight), horzResolution, vertResolution))
}

// FT_Get_Char_Index: 0 if the face has no glyph for it.
public func getCharIndex(face: Face, charcode: UInt32) -> UInt32 {
    FT_Get_Char_Index(face.pointer, FT_ULong(charcode))
}

// FT_Get_Kerning
public func getKerning(face: Face, leftGlyph: UInt32, rightGlyph: UInt32, kernMode: KerningMode) throws -> Vector {
    var kerning = FT_Vector()
    try check(
        "FT_Get_Kerning",
        FT_Get_Kerning(face.pointer, leftGlyph, rightGlyph, FT_UInt(kernMode.rawValue), &kerning))
    return Vector(kerning)
}
