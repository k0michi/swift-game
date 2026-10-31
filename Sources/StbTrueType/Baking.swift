import CStbTrueType

// stbtt_bakedchar
public struct BakedChar: Equatable, Sendable {
    public var x0, y0, x1, y1: UInt16
    public var xoff, yoff, xadvance: Float

    init(_ char: stbtt_bakedchar) {
        (x0, y0, x1, y1) = (char.x0, char.y0, char.x1, char.y1)
        (xoff, yoff, xadvance) = (char.xoff, char.yoff, char.xadvance)
    }

    var c: stbtt_bakedchar {
        stbtt_bakedchar(x0: x0, y0: y0, x1: x1, y1: y1, xoff: xoff, yoff: yoff, xadvance: xadvance)
    }
}

// stbtt_packedchar
public struct PackedChar: Equatable, Sendable {
    public var x0, y0, x1, y1: UInt16
    public var xoff, yoff, xadvance: Float
    public var xoff2, yoff2: Float

    init(_ char: stbtt_packedchar) {
        (x0, y0, x1, y1) = (char.x0, char.y0, char.x1, char.y1)
        (xoff, yoff, xadvance) = (char.xoff, char.yoff, char.xadvance)
        (xoff2, yoff2) = (char.xoff2, char.yoff2)
    }

    var c: stbtt_packedchar {
        stbtt_packedchar(
            x0: x0, y0: y0, x1: x1, y1: y1, xoff: xoff, yoff: yoff, xadvance: xadvance, xoff2: xoff2, yoff2: yoff2)
    }
}

// stbtt_aligned_quad
public struct AlignedQuad: Equatable, Sendable {
    public var x0, y0, s0, t0: Float
    public var x1, y1, s1, t1: Float

    init(_ quad: stbtt_aligned_quad) {
        (x0, y0, s0, t0) = (quad.x0, quad.y0, quad.s0, quad.t0)
        (x1, y1, s1, t1) = (quad.x1, quad.y1, quad.s1, quad.t1)
    }
}

// stbtt_BakeFontBitmap: bakes num_chars characters from first_char into a
// pw x ph bitmap. The result is the first unused row, or minus the number
// of characters that fit if not all did.
public func bakeFontBitmap(
    data: [UInt8], offset: Int32 = 0, pixelHeight: Float, pw: Int32, ph: Int32, firstChar: Int32, numChars: Int32
) throws -> (result: Int32, pixels: [UInt8], chardata: [BakedChar]) {
    precondition(pw > 0 && ph > 0 && numChars >= 0)
    // It reads the font's tables wherever they say they are, so it checks
    // first that it is a font.
    _ = try initFont(data: data, offset: offset)
    var pixels = [UInt8](repeating: 0, count: Int(pw) * Int(ph))
    var chardata = [stbtt_bakedchar](repeating: stbtt_bakedchar(), count: Int(numChars))
    let result = stbtt_BakeFontBitmap(data, offset, pixelHeight, &pixels, pw, ph, firstChar, numChars, &chardata)
    return (result, pixels, chardata.map(BakedChar.init))
}

// stbtt_GetBakedQuad: the quad of char_index, moving xpos past it.
public func getBakedQuad(
    chardata: [BakedChar], pw: Int32, ph: Int32, charIndex: Int32, xpos: inout Float, ypos: inout Float,
    openglFillrule: Bool
) -> AlignedQuad {
    precondition(chardata.indices.contains(Int(charIndex)))
    var quad = stbtt_aligned_quad()
    stbtt_GetBakedQuad(chardata.map(\.c), pw, ph, charIndex, &xpos, &ypos, &quad, openglFillrule ? 1 : 0)
    return AlignedQuad(quad)
}

// stbtt_pack_context with the bitmap it packs into, which live as long as
// it. stbtt_PackEnd frees what it packs with.
public final class PackContext {
    let pointer: UnsafeMutablePointer<stbtt_pack_context>
    private let bitmap: UnsafeMutableBufferPointer<UInt8>
    fileprivate var ended = false

    fileprivate init(pointer: UnsafeMutablePointer<stbtt_pack_context>, bitmap: UnsafeMutableBufferPointer<UInt8>) {
        self.pointer = pointer
        self.bitmap = bitmap
    }

    /// The bitmap, a byte of coverage for each pixel, rows stride_in_bytes
    /// apart.
    public var pixels: [UInt8] {
        Array(bitmap)
    }

    deinit {
        if !ended {
            stbtt_PackEnd(pointer)
        }
        pointer.deallocate()
        bitmap.deallocate()
    }
}

// stbtt_PackBegin: packs into a width x height bitmap of its own, rows
// stride_in_bytes apart, or packed when it is 0.
public func packBegin(width: Int32, height: Int32, strideInBytes: Int32 = 0, padding: Int32 = 1) throws -> PackContext {
    precondition(width > 0 && height > 0 && (strideInBytes == 0 || strideInBytes >= width))
    let stride = strideInBytes == 0 ? width : strideInBytes
    let bitmap = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: Int(stride) * Int(height))
    bitmap.initialize(repeating: 0)
    let pointer = UnsafeMutablePointer<stbtt_pack_context>.allocate(capacity: 1)
    guard stbtt_PackBegin(pointer, bitmap.baseAddress, width, height, strideInBytes, padding, nil) != 0 else {
        pointer.deallocate()
        bitmap.deallocate()
        throw StbTrueTypeError(operation: "stbtt_PackBegin", message: "out of memory")
    }
    return PackContext(pointer: pointer, bitmap: bitmap)
}

// stbtt_PackEnd: the context's bitmap stays.
public func packEnd(spc: PackContext) {
    guard !spc.ended else { return }
    stbtt_PackEnd(spc.pointer)
    spc.ended = true
}

// stbtt_PackSetOversampling
public func packSetOversampling(spc: PackContext, hOversample: UInt32, vOversample: UInt32) {
    precondition(!spc.ended)
    stbtt_PackSetOversampling(spc.pointer, hOversample, vOversample)
}

// stbtt_PackSetSkipMissingCodepoints
public func packSetSkipMissingCodepoints(spc: PackContext, skip: Bool) {
    precondition(!spc.ended)
    stbtt_PackSetSkipMissingCodepoints(spc.pointer, skip ? 1 : 0)
}

// stbtt_PackFontRange: packs num_chars_in_range characters from
// first_unicode_codepoint_in_range of the font_index'th font of fontdata.
// font_size is in pixels, or in ems when negative, as STBTT_POINT_SIZE
// makes it. It throws if not all of them fit.
public func packFontRange(
    spc: PackContext, fontdata: [UInt8], fontIndex: Int32 = 0, fontSize: Float,
    firstUnicodeCodepointInRange: Int32, numCharsInRange: Int32
) throws -> [PackedChar] {
    precondition(!spc.ended && numCharsInRange >= 0)
    let offset = getFontOffsetForIndex(data: fontdata, index: fontIndex)
    guard offset >= 0 else {
        throw StbTrueTypeError(operation: "stbtt_PackFontRange", message: "no font \(fontIndex)")
    }
    _ = try initFont(data: fontdata, offset: offset)
    var chardata = [stbtt_packedchar](repeating: stbtt_packedchar(), count: Int(numCharsInRange))
    guard stbtt_PackFontRange(
        spc.pointer, fontdata, fontIndex, fontSize, firstUnicodeCodepointInRange, numCharsInRange, &chardata
    ) != 0 else {
        throw StbTrueTypeError(operation: "stbtt_PackFontRange", message: "not all characters fit")
    }
    return chardata.map(PackedChar.init)
}

// stbtt_GetPackedQuad: the quad of char_index, moving xpos past it.
public func getPackedQuad(
    chardata: [PackedChar], pw: Int32, ph: Int32, charIndex: Int32, xpos: inout Float, ypos: inout Float,
    alignToInteger: Bool
) -> AlignedQuad {
    precondition(chardata.indices.contains(Int(charIndex)))
    var quad = stbtt_aligned_quad()
    stbtt_GetPackedQuad(chardata.map(\.c), pw, ph, charIndex, &xpos, &ypos, &quad, alignToInteger ? 1 : 0)
    return AlignedQuad(quad)
}
