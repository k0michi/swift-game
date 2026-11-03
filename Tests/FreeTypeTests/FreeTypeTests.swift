import Foundation
import Testing

@testable import FreeType

// 1000 units to the em, 800 above the baseline and 200 below. "A" is a
// 500-unit square and "B" a 500 x 700 rectangle, each 100 units in and 700
// across, and A is kerned 100 closer to B. Tests/StbTests/make-test-font.py
// made it.
private let squares = Array(
    FileManager.default.contents(
        atPath: Bundle.module.path(forResource: "squares", ofType: "ttf", inDirectory: "Resources")!)!)
private let a = UnicodeScalar("A").value
private let b = UnicodeScalar("B").value

@Suite("FreeType")
struct FreeTypeTests {
    @Test
    func readsTheFace() throws {
        let library = try initFreeType()
        #expect(libraryVersion(library: library) == (2, 15, 0))
        let face = try newMemoryFace(library: library, fileBase: squares)
        #expect(face.numFaces == 1)
        #expect(face.numGlyphs == 4)
        #expect(face.familyName == "Squares")
        #expect(face.styleName == "Regular")
        #expect((face.unitsPerEM, face.ascender, face.descender) == (1000, 800, -200))
        #expect(getCharIndex(face: face, charcode: a) != 0)
        #expect(getCharIndex(face: face, charcode: UnicodeScalar("Z").value) == 0)
    }

    @Test
    func rendersGlyphs() throws {
        let library = try initFreeType()
        let face = try newMemoryFace(library: library, fileBase: squares)
        try setPixelSizes(face: face, pixelWidth: 0, pixelHeight: 100)
        #expect((face.size.metrics.xPpem, face.size.metrics.yPpem) == (100, 100))

        // At 100 pixels to the em, A covers 50 x 50 pixels whole, 10 right of
        // the origin and above the baseline, and advances 70.
        try loadChar(face: face, charCode: a, loadFlags: [.render, .noHinting])
        let bitmap = face.glyph.bitmap
        #expect((bitmap.width, bitmap.rows, bitmap.pitch, bitmap.pixelMode) == (50, 50, 50, .gray))
        #expect(bitmap.buffer.count == 50 * 50 && bitmap.buffer.allSatisfy { $0 == 255 })
        #expect((face.glyph.bitmapLeft, face.glyph.bitmapTop) == (10, 50))
        #expect(face.glyph.advance == Vector(x: 70 * 64, y: 0))

        let glyphB = getCharIndex(face: face, charcode: b)
        try loadGlyph(face: face, glyphIndex: glyphB, loadFlags: .noHinting)
        #expect(face.glyph.glyphIndex == glyphB)
        #expect(face.glyph.bitmap.buffer.isEmpty)
        #expect(face.glyph.metrics.width == 50 * 64 && face.glyph.metrics.height == 70 * 64)
        try renderGlyph(slot: face.glyph, renderMode: .normal)
        #expect((face.glyph.bitmap.width, face.glyph.bitmap.rows) == (50, 70))
    }

    @Test
    func kerns() throws {
        let library = try initFreeType()
        let face = try newMemoryFace(library: library, fileBase: squares)
        let glyphA = getCharIndex(face: face, charcode: a)
        let glyphB = getCharIndex(face: face, charcode: b)
        #expect(try getKerning(face: face, leftGlyph: glyphA, rightGlyph: glyphB, kernMode: .unscaled) == Vector(x: -100, y: 0))
        #expect(try getKerning(face: face, leftGlyph: glyphB, rightGlyph: glyphA, kernMode: .unscaled) == Vector(x: 0, y: 0))
    }

    @Test
    func failsWhenItCannot() throws {
        let library = try initFreeType()
        #expect(throws: FreeTypeError(operation: "FT_New_Memory_Face", code: 0x55)) {
            try newMemoryFace(library: library, fileBase: Array("not a font".utf8))
        }
        let face = try newMemoryFace(library: library, fileBase: squares)
        #expect(throws: FreeTypeError(operation: "FT_Load_Glyph", code: 0x06)) {
            try loadGlyph(face: face, glyphIndex: 100, loadFlags: .default)
        }
    }
}
