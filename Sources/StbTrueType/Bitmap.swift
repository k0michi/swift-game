import CStbTrueType

// Copies a bitmap stb_truetype allocated and frees it with `free`.
private func takeBitmap(
    _ free: (UnsafeMutablePointer<UInt8>) -> Void,
    _ make: (_ width: inout Int32, _ height: inout Int32, _ xoff: inout Int32, _ yoff: inout Int32) -> UnsafeMutablePointer<UInt8>?
) -> (bitmap: [UInt8], width: Int32, height: Int32, xoff: Int32, yoff: Int32) {
    var width: Int32 = 0
    var height: Int32 = 0
    var xoff: Int32 = 0
    var yoff: Int32 = 0
    // An empty glyph, such as a space, has no bitmap.
    guard let pixels = make(&width, &height, &xoff, &yoff) else { return ([], 0, 0, xoff, yoff) }
    defer { free(pixels) }
    return (Array(UnsafeBufferPointer(start: pixels, count: Int(width) * Int(height))), width, height, xoff, yoff)
}

// The output must hold out_h rows out_stride apart of out_w pixels.
private func checkOutput(_ output: UnsafeMutableRawBufferPointer, outW: Int32, outH: Int32, outStride: Int32) {
    precondition(outW >= 0 && outH >= 0 && outStride >= outW, "invalid bitmap size")
    precondition(outW == 0 || outH == 0 || output.count >= Int(outH - 1) * Int(outStride) + Int(outW), "output is too small")
}

// stbtt_GetCodepointBitmap with stbtt_FreeBitmap
public func getCodepointBitmap(
    info: FontInfo, scaleX: Float, scaleY: Float, codepoint: Int32
) -> (bitmap: [UInt8], width: Int32, height: Int32, xoff: Int32, yoff: Int32) {
    takeBitmap({ stbtt_FreeBitmap($0, nil) }) { width, height, xoff, yoff in
        stbtt_GetCodepointBitmap(info.pointer, scaleX, scaleY, codepoint, &width, &height, &xoff, &yoff)
    }
}

// stbtt_GetGlyphBitmap with stbtt_FreeBitmap
public func getGlyphBitmap(
    info: FontInfo, scaleX: Float, scaleY: Float, glyph: Int32
) -> (bitmap: [UInt8], width: Int32, height: Int32, xoff: Int32, yoff: Int32) {
    takeBitmap({ stbtt_FreeBitmap($0, nil) }) { width, height, xoff, yoff in
        stbtt_GetGlyphBitmap(info.pointer, scaleX, scaleY, glyph, &width, &height, &xoff, &yoff)
    }
}

// stbtt_GetCodepointSDF with stbtt_FreeSDF
public func getCodepointSDF(
    info: FontInfo, scale: Float, codepoint: Int32, padding: Int32, onedgeValue: UInt8, pixelDistScale: Float
) -> (bitmap: [UInt8], width: Int32, height: Int32, xoff: Int32, yoff: Int32) {
    takeBitmap({ stbtt_FreeSDF($0, nil) }) { width, height, xoff, yoff in
        stbtt_GetCodepointSDF(
            info.pointer, scale, codepoint, padding, onedgeValue, pixelDistScale, &width, &height, &xoff, &yoff)
    }
}

// stbtt_GetGlyphSDF with stbtt_FreeSDF
public func getGlyphSDF(
    info: FontInfo, scale: Float, glyph: Int32, padding: Int32, onedgeValue: UInt8, pixelDistScale: Float
) -> (bitmap: [UInt8], width: Int32, height: Int32, xoff: Int32, yoff: Int32) {
    takeBitmap({ stbtt_FreeSDF($0, nil) }) { width, height, xoff, yoff in
        stbtt_GetGlyphSDF(info.pointer, scale, glyph, padding, onedgeValue, pixelDistScale, &width, &height, &xoff, &yoff)
    }
}

// stbtt_GetCodepointBitmapBox
public func getCodepointBitmapBox(
    font: FontInfo, codepoint: Int32, scaleX: Float, scaleY: Float
) -> (ix0: Int32, iy0: Int32, ix1: Int32, iy1: Int32) {
    var ix0: Int32 = 0
    var iy0: Int32 = 0
    var ix1: Int32 = 0
    var iy1: Int32 = 0
    stbtt_GetCodepointBitmapBox(font.pointer, codepoint, scaleX, scaleY, &ix0, &iy0, &ix1, &iy1)
    return (ix0, iy0, ix1, iy1)
}

// stbtt_GetGlyphBitmapBox
public func getGlyphBitmapBox(
    font: FontInfo, glyph: Int32, scaleX: Float, scaleY: Float
) -> (ix0: Int32, iy0: Int32, ix1: Int32, iy1: Int32) {
    var ix0: Int32 = 0
    var iy0: Int32 = 0
    var ix1: Int32 = 0
    var iy1: Int32 = 0
    stbtt_GetGlyphBitmapBox(font.pointer, glyph, scaleX, scaleY, &ix0, &iy0, &ix1, &iy1)
    return (ix0, iy0, ix1, iy1)
}

// stbtt_MakeCodepointBitmap: draws into `output`, clipped to out_w x out_h.
public func makeCodepointBitmap(
    info: FontInfo, output: UnsafeMutableRawBufferPointer, outW: Int32, outH: Int32, outStride: Int32,
    scaleX: Float, scaleY: Float, codepoint: Int32
) {
    checkOutput(output, outW: outW, outH: outH, outStride: outStride)
    stbtt_MakeCodepointBitmap(
        info.pointer, output.baseAddress?.assumingMemoryBound(to: UInt8.self), outW, outH, outStride,
        scaleX, scaleY, codepoint)
}

// stbtt_MakeGlyphBitmap: draws into `output`, clipped to out_w x out_h.
public func makeGlyphBitmap(
    info: FontInfo, output: UnsafeMutableRawBufferPointer, outW: Int32, outH: Int32, outStride: Int32,
    scaleX: Float, scaleY: Float, glyph: Int32
) {
    checkOutput(output, outW: outW, outH: outH, outStride: outStride)
    stbtt_MakeGlyphBitmap(
        info.pointer, output.baseAddress?.assumingMemoryBound(to: UInt8.self), outW, outH, outStride,
        scaleX, scaleY, glyph)
}
