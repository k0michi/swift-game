import Foundation
import Testing

@testable import StbTrueType

// 1000 units to the em, 800 above the baseline and 200 below. "A" is a
// 500-unit square and "B" a 500 x 700 rectangle, each 100 units in and 700
// across, and A is kerned 100 closer to B. make-test-font.py made it.
private let squares = Array(
    FileManager.default.contents(
        atPath: Bundle.module.path(forResource: "squares", ofType: "ttf", inDirectory: "Resources")!)!)
private let a = Int32(UnicodeScalar("A").value)
private let b = Int32(UnicodeScalar("B").value)
private let space = Int32(UnicodeScalar(" ").value)

@Suite("stb_truetype")
struct TrueTypeTests {
    @Test
    func readsTheMetrics() throws {
        #expect(getNumberOfFonts(data: squares) == 1)
        #expect(getFontOffsetForIndex(data: squares, index: 0) == 0)
        #expect(getFontOffsetForIndex(data: squares, index: 1) == -1)
        let font = try initFont(data: squares)
        #expect(getFontVMetrics(info: font) == (800, -200, 0))
        #expect(getFontBoundingBox(info: font) == (100, 0, 600, 700))
        #expect(scaleForPixelHeight(info: font, height: 100) == 0.1)
        #expect(scaleForMappingEmToPixels(info: font, pixels: 50) == 0.05)
        #expect(getCodepointHMetrics(info: font, codepoint: a) == (700, 100))
        #expect(getCodepointKernAdvance(info: font, ch1: a, ch2: b) == -100)
        #expect(getCodepointKernAdvance(info: font, ch1: b, ch2: a) == 0)
        #expect(getCodepointBox(info: font, codepoint: a)! == (100, 0, 600, 500))
        #expect(getCodepointBox(info: font, codepoint: space) == nil)
    }

    @Test
    func findsGlyphs() throws {
        let font = try initFont(data: squares)
        let glyphA = findGlyphIndex(info: font, unicodeCodepoint: a)
        let glyphB = findGlyphIndex(info: font, unicodeCodepoint: b)
        #expect(glyphA != 0 && glyphB != 0)
        #expect(findGlyphIndex(info: font, unicodeCodepoint: Int32(UnicodeScalar("Z").value)) == 0)
        #expect(getGlyphHMetrics(info: font, glyphIndex: glyphB) == (700, 100))
        #expect(getGlyphKernAdvance(info: font, glyph1: glyphA, glyph2: glyphB) == -100)
        #expect(getGlyphBox(info: font, glyphIndex: glyphB)! == (100, 0, 600, 700))
        #expect(isGlyphEmpty(info: font, glyphIndex: findGlyphIndex(info: font, unicodeCodepoint: space)))
        #expect(!isGlyphEmpty(info: font, glyphIndex: glyphA))
    }

    @Test
    func rasterizesGlyphs() throws {
        let font = try initFont(data: squares)
        // At a tenth, A covers 50 x 50 pixels whole, 10 right of the origin
        // and above the baseline.
        let glyph = getCodepointBitmap(info: font, scaleX: 0.1, scaleY: 0.1, codepoint: a)
        #expect((glyph.width, glyph.height, glyph.xoff, glyph.yoff) == (50, 50, 10, -50))
        #expect(glyph.bitmap.allSatisfy { $0 == 255 })
        #expect(getCodepointBitmapBox(font: font, codepoint: a, scaleX: 0.1, scaleY: 0.1) == (10, -50, 60, 0))
        #expect(getCodepointBitmap(info: font, scaleX: 0.1, scaleY: 0.1, codepoint: space).bitmap.isEmpty)

        let glyphB = findGlyphIndex(info: font, unicodeCodepoint: b)
        #expect(getGlyphBitmap(info: font, scaleX: 0.1, scaleY: 0.1, glyph: glyphB).height == 70)
        #expect(getGlyphBitmapBox(font: font, glyph: glyphB, scaleX: 0.1, scaleY: 0.1) == (10, -70, 60, 0))
    }

    @Test
    func drawsIntoABitmap() throws {
        let font = try initFont(data: squares)
        // Rows 64 bytes apart, of which 40 are drawn: A's 50 pixels across
        // are clipped to 40.
        var output = [UInt8](repeating: 0, count: 64 * 60)
        output.withUnsafeMutableBytes {
            makeCodepointBitmap(
                info: font, output: $0, outW: 40, outH: 60, outStride: 64, scaleX: 0.1, scaleY: 0.1, codepoint: a)
        }
        #expect(output.filter { $0 == 255 }.count == 40 * 50)
        #expect((0..<60).allSatisfy { row in output[(row * 64 + 40)..<(row * 64 + 64)].allSatisfy { $0 == 0 } })
    }

    @Test
    func makesSignedDistanceFields() throws {
        let font = try initFont(data: squares)
        let sdf = getCodepointSDF(
            info: font, scale: 0.1, codepoint: a, padding: 4, onedgeValue: 128, pixelDistScale: 16)
        #expect((sdf.width, sdf.height) == (58, 58))
        // Inside is above the edge's value and outside below it.
        #expect(sdf.bitmap[29 * 58 + 29] > 128)
        #expect(sdf.bitmap[0] < 128)
    }

    @Test
    func bakesCharactersIntoABitmap() throws {
        let baked = try bakeFontBitmap(
            data: squares, pixelHeight: 100, pw: 256, ph: 128, firstChar: space, numChars: b - space + 1)
        #expect(baked.result > 0)
        #expect(baked.pixels.filter { $0 == 255 }.count == 50 * 50 + 50 * 70)
        var x: Float = 0
        var y: Float = 0
        let quad = getBakedQuad(
            chardata: baked.chardata, pw: 256, ph: 128, charIndex: a - space, xpos: &x, ypos: &y, openglFillrule: true)
        #expect((quad.x1 - quad.x0, quad.y1 - quad.y0) == (50, 50))
        #expect(x == 70)
    }

    @Test
    func packsCharactersIntoABitmap() throws {
        let context = try packBegin(width: 128, height: 128)
        let chars = try packFontRange(
            spc: context, fontdata: squares, fontSize: 100, firstUnicodeCodepointInRange: a, numCharsInRange: 2)
        packEnd(spc: context)
        #expect(context.pixels.filter { $0 == 255 }.count == 50 * 50 + 50 * 70)
        var x: Float = 0
        var y: Float = 0
        let quad = getPackedQuad(chardata: chars, pw: 128, ph: 128, charIndex: 1, xpos: &x, ypos: &y, alignToInteger: true)
        #expect((quad.x1 - quad.x0, quad.y1 - quad.y0) == (50, 70))
        #expect(x == 70)
    }

    @Test
    func failsWhenItCannot() throws {
        #expect(throws: StbTrueTypeError(operation: "stbtt_InitFont", message: "not a font")) {
            try initFont(data: Array("not a font".utf8))
        }
        let context = try packBegin(width: 16, height: 16)
        #expect(throws: StbTrueTypeError(operation: "stbtt_PackFontRange", message: "not all characters fit")) {
            try packFontRange(
                spc: context, fontdata: squares, fontSize: 100, firstUnicodeCodepointInRange: a, numCharsInRange: 2)
        }
    }
}
