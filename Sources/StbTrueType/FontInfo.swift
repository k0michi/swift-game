import CStbTrueType

// stbtt_fontinfo with the font file it reads, which stbtt_InitFont does not
// copy, so a copy lives as long as it.
public final class FontInfo {
    let pointer: UnsafeMutablePointer<stbtt_fontinfo>
    private let data: UnsafeMutableBufferPointer<UInt8>

    fileprivate init(pointer: UnsafeMutablePointer<stbtt_fontinfo>, data: UnsafeMutableBufferPointer<UInt8>) {
        self.pointer = pointer
        self.data = data
    }

    deinit {
        pointer.deallocate()
        data.deallocate()
    }
}

// stbtt_GetNumberOfFonts
public func getNumberOfFonts(data: [UInt8]) -> Int32 {
    stbtt_GetNumberOfFonts(data)
}

// stbtt_GetFontOffsetForIndex: -1 if there is no such font.
public func getFontOffsetForIndex(data: [UInt8], index: Int32) -> Int32 {
    stbtt_GetFontOffsetForIndex(data, index)
}

// stbtt_InitFont
public func initFont(data: [UInt8], offset: Int32 = 0) throws -> FontInfo {
    let copy = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: max(data.count, 1))
    _ = copy.initialize(from: data)
    let pointer = UnsafeMutablePointer<stbtt_fontinfo>.allocate(capacity: 1)
    // stb_truetype trusts the file's offsets, so it reads only a real font.
    guard !data.isEmpty, stbtt_InitFont(pointer, copy.baseAddress, offset) != 0 else {
        pointer.deallocate()
        copy.deallocate()
        throw StbTrueTypeError(operation: "stbtt_InitFont", message: "not a font")
    }
    return FontInfo(pointer: pointer, data: copy)
}

// stbtt_FindGlyphIndex: 0 if the font has no glyph for it.
public func findGlyphIndex(info: FontInfo, unicodeCodepoint: Int32) -> Int32 {
    stbtt_FindGlyphIndex(info.pointer, unicodeCodepoint)
}

// stbtt_ScaleForPixelHeight
public func scaleForPixelHeight(info: FontInfo, height: Float) -> Float {
    stbtt_ScaleForPixelHeight(info.pointer, height)
}

// stbtt_ScaleForMappingEmToPixels
public func scaleForMappingEmToPixels(info: FontInfo, pixels: Float) -> Float {
    stbtt_ScaleForMappingEmToPixels(info.pointer, pixels)
}

// stbtt_GetFontVMetrics
public func getFontVMetrics(info: FontInfo) -> (ascent: Int32, descent: Int32, lineGap: Int32) {
    var ascent: Int32 = 0
    var descent: Int32 = 0
    var lineGap: Int32 = 0
    stbtt_GetFontVMetrics(info.pointer, &ascent, &descent, &lineGap)
    return (ascent, descent, lineGap)
}

// stbtt_GetFontBoundingBox
public func getFontBoundingBox(info: FontInfo) -> (x0: Int32, y0: Int32, x1: Int32, y1: Int32) {
    var x0: Int32 = 0
    var y0: Int32 = 0
    var x1: Int32 = 0
    var y1: Int32 = 0
    stbtt_GetFontBoundingBox(info.pointer, &x0, &y0, &x1, &y1)
    return (x0, y0, x1, y1)
}

// stbtt_GetCodepointHMetrics
public func getCodepointHMetrics(info: FontInfo, codepoint: Int32) -> (advanceWidth: Int32, leftSideBearing: Int32) {
    var advanceWidth: Int32 = 0
    var leftSideBearing: Int32 = 0
    stbtt_GetCodepointHMetrics(info.pointer, codepoint, &advanceWidth, &leftSideBearing)
    return (advanceWidth, leftSideBearing)
}

// stbtt_GetCodepointKernAdvance
public func getCodepointKernAdvance(info: FontInfo, ch1: Int32, ch2: Int32) -> Int32 {
    stbtt_GetCodepointKernAdvance(info.pointer, ch1, ch2)
}

// stbtt_GetCodepointBox: nil if the glyph has no outline.
public func getCodepointBox(info: FontInfo, codepoint: Int32) -> (x0: Int32, y0: Int32, x1: Int32, y1: Int32)? {
    var x0: Int32 = 0
    var y0: Int32 = 0
    var x1: Int32 = 0
    var y1: Int32 = 0
    guard stbtt_GetCodepointBox(info.pointer, codepoint, &x0, &y0, &x1, &y1) != 0 else { return nil }
    return (x0, y0, x1, y1)
}

// stbtt_GetGlyphHMetrics
public func getGlyphHMetrics(info: FontInfo, glyphIndex: Int32) -> (advanceWidth: Int32, leftSideBearing: Int32) {
    var advanceWidth: Int32 = 0
    var leftSideBearing: Int32 = 0
    stbtt_GetGlyphHMetrics(info.pointer, glyphIndex, &advanceWidth, &leftSideBearing)
    return (advanceWidth, leftSideBearing)
}

// stbtt_GetGlyphKernAdvance
public func getGlyphKernAdvance(info: FontInfo, glyph1: Int32, glyph2: Int32) -> Int32 {
    stbtt_GetGlyphKernAdvance(info.pointer, glyph1, glyph2)
}

// stbtt_GetGlyphBox: nil if the glyph has no outline.
public func getGlyphBox(info: FontInfo, glyphIndex: Int32) -> (x0: Int32, y0: Int32, x1: Int32, y1: Int32)? {
    var x0: Int32 = 0
    var y0: Int32 = 0
    var x1: Int32 = 0
    var y1: Int32 = 0
    guard stbtt_GetGlyphBox(info.pointer, glyphIndex, &x0, &y0, &x1, &y1) != 0 else { return nil }
    return (x0, y0, x1, y1)
}

// stbtt_IsGlyphEmpty
public func isGlyphEmpty(info: FontInfo, glyphIndex: Int32) -> Bool {
    stbtt_IsGlyphEmpty(info.pointer, glyphIndex) != 0
}
