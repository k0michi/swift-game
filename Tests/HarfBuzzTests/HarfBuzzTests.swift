import Foundation
import Testing

@testable import HarfBuzz

// 1000 units to the em, 800 above the baseline and 200 below. "A" is a
// 500-unit square and "B" a 500 x 700 rectangle, each 100 units in and 700
// across, and A is kerned 100 closer to B. Tests/StbTests/make-test-font.py
// made it.
private let squares = Array(
    FileManager.default.contents(
        atPath: Bundle.module.path(forResource: "squares", ofType: "ttf", inDirectory: "Resources")!)!)

@Suite("HarfBuzz")
struct HarfBuzzTests {
    @Test
    func readsTheFace() {
        #expect(version() == (15, 0, 0))
        #expect(versionString() == "15.0.0")
        let blob = blobCreate(data: squares)
        #expect(blobGetLength(blob: blob) == UInt32(squares.count))
        let face = faceCreate(blob: blob, index: 0)
        #expect(faceGetUpem(face: face) == 1000)
        #expect(faceGetGlyphCount(face: face) == 4)
        // The scale is the face's units until it is set.
        let font = fontCreate(face: face)
        #expect(fontGetScale(font: font) == (1000, 1000))
        fontSetScale(font: font, xScale: 64_000, yScale: 64_000)
        #expect(fontGetScale(font: font) == (64_000, 64_000))
    }

    @Test
    func shapes() {
        let font = fontCreate(face: faceCreate(blob: blobCreate(data: squares), index: 0))
        let buffer = bufferCreate()
        bufferAddUTF8(buffer: buffer, text: "ABZ")
        #expect(bufferGetLength(buffer: buffer) == 3)
        bufferGuessSegmentProperties(buffer: buffer)
        #expect(bufferGetDirection(buffer: buffer) == .ltr)
        #expect(bufferGetScript(buffer: buffer) == .latin)
        shape(font: font, buffer: buffer)

        // A, B and the missing glyph for Z, each from its own character. The
        // kerning of A to B is shared between them: B moves 50 back of where
        // A puts it, and itself puts Z 50 closer.
        let infos = bufferGetGlyphInfos(buffer: buffer)
        #expect(infos.map(\.codepoint) == [2, 3, 0])
        #expect(infos.map(\.cluster) == [0, 1, 2])
        let positions = bufferGetGlyphPositions(buffer: buffer)
        #expect(positions.map(\.xAdvance) == [650, 650, 500])
        #expect(positions.map(\.xOffset) == [0, -50, 0])
    }

    @Test
    func turnsFeaturesOff() throws {
        let font = fontCreate(face: faceCreate(blob: blobCreate(data: squares), index: 0))
        let buffer = bufferCreate()
        bufferAddUTF8(buffer: buffer, text: "AB")
        bufferSetDirection(buffer: buffer, direction: .ltr)
        bufferSetScript(buffer: buffer, script: scriptFromString(str: "Latn"))
        bufferSetLanguage(buffer: buffer, language: languageFromString(str: "en"))
        #expect(languageToString(language: bufferGetLanguage(buffer: buffer)) == "en")
        shape(font: font, buffer: buffer, features: [try #require(featureFromString(str: "-kern"))])
        #expect(bufferGetGlyphPositions(buffer: buffer).map(\.xAdvance) == [700, 700])
        #expect(featureFromString(str: "") == nil)
    }

    @Test
    func readsNothingFromWhatIsNotAFont() {
        let face = faceCreate(blob: blobCreate(data: Array("not a font".utf8)), index: 0)
        #expect(faceGetGlyphCount(face: face) == 0)
    }
}
