import Dawn
import FreeType
import HarfBuzz

// A glyph at a size, which the atlas holds once.
struct GlyphKey: Hashable {
    var index: UInt32
    var pixelSize: UInt32
}

// Where a glyph's bitmap is in the atlas, and how it sits on the pen's
// position: `left` right of it and `top` above the baseline.
struct AtlasGlyph {
    var x: Int
    var y: Int
    var width: Int
    var height: Int
    var left: Int
    var top: Int
}

// A string shaped at a size: its glyphs at their pen positions, where each of
// its clusters begins, by its UTF-8 offset in the string, and its width, in
// 26.6 fixed point, and its ascender, descender and line height in pixels.
struct ShapedRun {
    var glyphs: [(key: GlyphKey, x: Int, y: Int)]
    var clusters: [(offset: Int, x: Int)]
    var width: Int
    var ascender: Int
    var descender: Int
    var lineHeight: Int
}

private struct RunKey: Hashable {
    var text: String
    var pixelSize: UInt32
}

/// Text in a font: shaped by HarfBuzz the first time each string is asked for
/// at a size, and its glyphs rasterized by FreeType into the atlas the first
/// time they are drawn, and drawn as quads. It is registered with its font.
final class Typesetter: GraphicsResource {
    private unowned let compositor: Compositor
    private let library: Library
    private let face: FreeType.Face
    private let shaper: HarfBuzz.Font
    private var facePixelSize: UInt32 = 0

    private var glyphs: [GlyphKey: AtlasGlyph] = [:]
    private var atlasGeneration = 0

    // Runs shaped for this frame, and for the one before, which are dropped
    // unless this one asks for them too.
    private var runs: [RunKey: ShapedRun] = [:]
    private var previousRuns: [RunKey: ShapedRun] = [:]

    init(compositor: Compositor, font: [UInt8]) throws {
        self.compositor = compositor
        library = try initFreeType()
        face = try newMemoryFace(library: library, fileBase: font)
        shaper = fontCreate(face: faceCreate(blob: blobCreate(data: font), index: 0))
    }

    func beginFrame() {
        previousRuns = runs
        runs = [:]
    }

    /// `text` shaped at `points` to the em.
    func run(_ text: String, points: Float) -> ShapedRun {
        let key = RunKey(text: text, pixelSize: UInt32((points * compositor.scale).rounded()))
        if let run = runs[key] ?? previousRuns[key] {
            runs[key] = run
            return run
        }
        setFacePixelSize(key.pixelSize)
        let buffer = bufferCreate()
        bufferAddUTF8(buffer: buffer, text: text)
        bufferGuessSegmentProperties(buffer: buffer)
        // In 26.6 fixed point, as FreeType measures.
        fontSetScale(font: shaper, xScale: Int32(key.pixelSize) * 64, yScale: Int32(key.pixelSize) * 64)
        shape(font: shaper, buffer: buffer)

        var glyphs: [(key: GlyphKey, x: Int, y: Int)] = []
        var clusters: [(offset: Int, x: Int)] = []
        var penX = 0
        for (info, position) in zip(bufferGetGlyphInfos(buffer: buffer), bufferGetGlyphPositions(buffer: buffer)) {
            if clusters.last?.offset != Int(info.cluster) {
                clusters.append((Int(info.cluster), penX))
            }
            glyphs.append(
                (GlyphKey(index: info.codepoint, pixelSize: key.pixelSize), penX + Int(position.xOffset),
                 Int(position.yOffset)))
            penX += Int(position.xAdvance)
        }
        let run = ShapedRun(
            glyphs: glyphs, clusters: clusters, width: penX, ascender: face.size.metrics.ascender / 64,
            descender: face.size.metrics.descender / 64, lineHeight: face.size.metrics.height / 64)
        runs[key] = run
        return run
    }

    /// `text` shaped at `points` to the em, in lines no wider than `width`
    /// points, if there is a width, broken where `lineBreaks` allows, and at
    /// its newlines.
    func lines(_ text: String, points: Float, width: Float?) -> [ShapedRun] {
        let paragraph = run(text, points: points)
        let maximum = width.map { Int(($0 * compositor.scale * 64).rounded(.down)) }
        let bytes = Array(text.utf8)
        return wrap(text, clusters: paragraph.clusters, width: paragraph.width, maximum: maximum).map {
            run(String(decoding: bytes[$0], as: UTF8.self), points: points)
        }
    }

    /// Records `run` with its top-left corner at `x`, `y` in points, in
    /// `color`, which is not premultiplied: a quad for each glyph.
    func draw(_ run: ShapedRun, x: Float, y: Float, color: Color) throws {
        let scale = compositor.scale
        let left = Int((x * scale).rounded())
        let baseline = Int((y * scale).rounded()) + run.ascender
        for (key, glyphX, glyphY) in run.glyphs {
            guard let glyph = try glyph(key), glyph.width > 0, glyph.height > 0 else { continue }
            compositor.draw(
                QuadKind.self,
                QuadKind.Item(
                    rectangle: Rect(
                        x: Float(left + (glyphX + 32) >> 6 + glyph.left),
                        y: Float(baseline - (glyphY + 32) >> 6 - glyph.top), width: Float(glyph.width),
                        height: Float(glyph.height)),
                    texel: (Float(glyph.x), Float(glyph.y)), texels: (Float(glyph.width), Float(glyph.height)),
                    color: color))
        }
    }

    // The glyph in the atlas, which it is rasterized into the first time,
    // or nil if the atlas has no room left for it this frame.
    private func glyph(_ key: GlyphKey) throws -> AtlasGlyph? {
        let atlas = try compositor.resource(TextureAtlas.self)
        if atlas.generation != atlasGeneration {
            glyphs = [:]
            atlasGeneration = atlas.generation
        }
        if let glyph = glyphs[key] { return glyph }
        setFacePixelSize(key.pixelSize)
        try loadGlyph(face: face, glyphIndex: key.index, loadFlags: [.render, .targetLight])
        let bitmap = face.glyph.bitmap
        guard
            let origin = atlas.put(
                width: Int(bitmap.width), height: Int(bitmap.rows), pitch: Int(bitmap.pitch), pixels: bitmap.buffer)
        else { return nil }
        let glyph = AtlasGlyph(
            x: origin.x, y: origin.y, width: Int(bitmap.width), height: Int(bitmap.rows),
            left: Int(face.glyph.bitmapLeft), top: Int(face.glyph.bitmapTop))
        glyphs[key] = glyph
        return glyph
    }

    private func setFacePixelSize(_ pixelSize: UInt32) {
        guard pixelSize != facePixelSize else { return }
        try? setPixelSizes(face: face, pixelWidth: 0, pixelHeight: pixelSize)
        facePixelSize = pixelSize
    }
}

// What the views ask of text, from the compositor's typesetter.
extension Compositor {
    func run(_ text: String, points: Float) -> ShapedRun {
        try! resource(Typesetter.self).run(text, points: points)
    }

    func lines(_ text: String, points: Float, width: Float?) -> [ShapedRun] {
        try! resource(Typesetter.self).lines(text, points: points, width: width)
    }

    func draw(_ run: ShapedRun, x: Float, y: Float, color: Color) throws {
        try resource(Typesetter.self).draw(run, x: x, y: y, color: color)
    }
}
