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

// Draws text asked for as it is drawn: it shapes each string the first time
// it sees it at a size, and rasterizes each glyph the first time it needs it
// into one atlas texture, from which every glyph is drawn as an instance of
// one quad.
@MainActor
final class TextRenderer {
    // Pixels to the point, which the window's display sets.
    var scale: Float

    let device: Device
    /// The format of the texture it draws into.
    let format: TextureFormat
    private let library: Library
    private let face: FreeType.Face
    private let shaper: HarfBuzz.Font
    private var facePixelSize: UInt32 = 0

    private static let atlasSize = 1024
    private let atlas: Texture
    private var glyphs: [GlyphKey: AtlasGlyph] = [:]
    // The row of the atlas being filled, from its top and as high as its
    // highest glyph, and how far along it is.
    private var shelf = (x: 0, y: 0, height: 0)
    private var atlasIsFull = false

    // Runs shaped for this frame, and for the one before, which are dropped
    // unless this one asks for them too.
    private var runs: [RunKey: ShapedRun] = [:]
    private var previousRuns: [RunKey: ShapedRun] = [:]

    // Each instance is a rectangle in pixels, the atlas texel at its
    // top-left corner, how many texels it spans, a color, and the rectangle
    // in pixels it is clipped to. A filled rectangle spans no texels, of the
    // white one in the atlas's last corner.
    private static let floatsPerInstance = 16

    /// The rectangle in points that what is drawn is clipped to, if any.
    var clip: (x: Float, y: Float, width: Float, height: Float)?

    private var clipInPixels: [Float] {
        guard let clip else { return [-1e9, -1e9, 1e9, 1e9] }
        return [clip.x * scale, clip.y * scale, (clip.x + clip.width) * scale, (clip.y + clip.height) * scale]
    }
    private var instances: [Float] = []
    private var instanceBuffer: Dawn.Buffer?
    private var instanceBufferSize: UInt64 = 0
    private let screen: Dawn.Buffer
    private let pipeline: RenderPipeline
    private let bindGroup: BindGroup

    init(device: Device, format: TextureFormat, font: [UInt8], scale: Float) throws {
        self.device = device
        self.format = format
        self.scale = scale
        library = try initFreeType()
        face = try newMemoryFace(library: library, fileBase: font)
        shaper = fontCreate(face: faceCreate(blob: blobCreate(data: font), index: 0))

        let atlas = try device.createTexture(
            descriptor: TextureDescriptor(
                usage: [.textureBinding, .copyDst], dimension: .`2D`,
                size: Extent3D(
                    width: UInt32(Self.atlasSize), height: UInt32(Self.atlasSize), depthOrArrayLayers: 1),
                format: .r8Unorm))
        // The texel that filled rectangles are drawn from.
        [UInt8(255)].withUnsafeBytes { data in
            device.getQueue().writeTexture(
                destination: TexelCopyTextureInfo(
                    texture: atlas, origin: Origin3D(x: UInt32(Self.atlasSize - 1), y: UInt32(Self.atlasSize - 1))),
                data: data, dataLayout: TexelCopyBufferLayout(bytesPerRow: 1, rowsPerImage: 1),
                writeSize: Extent3D(width: 1, height: 1, depthOrArrayLayers: 1))
        }
        self.atlas = atlas
        screen = try device.createBuffer(
            descriptor: BufferDescriptor(label: "screen", usage: [.uniform, .copyDst], size: 8))

        let shaderModule = try device.createShaderModule(
            descriptor: ShaderModuleDescriptor(
                nextInChain: ShaderSourceWGSL(
                    code: """
                        @group(0) @binding(0) var atlas: texture_2d<f32>;
                        @group(0) @binding(1) var<uniform> screen: vec2f;

                        struct VertexOutput {
                            @builtin(position) position: vec4f,
                            @location(0) texel: vec2f,
                            @location(1) color: vec4f,
                            @location(2) clip: vec4f,
                        }

                        // A corner of the glyph's rectangle, in a strip of two
                        // triangles.
                        @vertex
                        fn vertexMain(
                            @builtin(vertex_index) index: u32,
                            @location(0) rectangle: vec4f,
                            @location(1) texel: vec2f,
                            @location(2) texels: vec2f,
                            @location(3) color: vec4f,
                            @location(4) clip: vec4f
                        ) -> VertexOutput {
                            let corner = vec2f(f32(index & 1u), f32(index >> 1u));
                            let pixel = rectangle.xy + corner * rectangle.zw;
                            var output: VertexOutput;
                            output.position = vec4f(pixel.x / screen.x * 2.0 - 1.0, 1.0 - pixel.y / screen.y * 2.0, 0.0, 1.0);
                            output.texel = texel + corner * texels;
                            output.color = color;
                            output.clip = clip;
                            return output;
                        }

                        // The glyph's pixels, one to one with the screen's.
                        @fragment
                        fn fragmentMain(
                            @builtin(position) position: vec4f,
                            @location(0) texel: vec2f,
                            @location(1) color: vec4f,
                            @location(2) clip: vec4f
                        ) -> @location(0) vec4f {
                            if (any(position.xy < clip.xy) || any(position.xy >= clip.zw)) {
                                discard;
                            }
                            return vec4f(color.rgb, color.a * textureLoad(atlas, vec2i(floor(texel)), 0).r);
                        }
                        """),
                label: "text"))
        let bindGroupLayout = try device.createBindGroupLayout(
            descriptor: BindGroupLayoutDescriptor(
                label: "text",
                entries: [
                    BindGroupLayoutEntry(
                        binding: 0, visibility: .fragment,
                        texture: TextureBindingLayout(sampleType: .float, viewDimension: .`2D`)),
                    BindGroupLayoutEntry(
                        binding: 1, visibility: .vertex, buffer: BufferBindingLayout(type: .uniform, minBindingSize: 8)),
                ]))
        bindGroup = try device.createBindGroup(
            descriptor: BindGroupDescriptor(
                label: "text", layout: bindGroupLayout,
                entries: [
                    BindGroupEntry(binding: 0, textureView: try atlas.createView()),
                    BindGroupEntry(binding: 1, buffer: screen),
                ]))
        let floatSize = UInt64(MemoryLayout<Float>.stride)
        pipeline = try device.createRenderPipeline(
            descriptor: RenderPipelineDescriptor(
                label: "text",
                layout: try device.createPipelineLayout(
                    descriptor: PipelineLayoutDescriptor(label: "text", bindGroupLayouts: [bindGroupLayout])),
                vertex: VertexState(
                    module: shaderModule, entryPoint: "vertexMain",
                    buffers: [
                        VertexBufferLayout(
                            stepMode: .instance,
                            arrayStride: UInt64(Self.floatsPerInstance) * floatSize,
                            attributes: [
                                VertexAttribute(format: .float32x4, offset: 0, shaderLocation: 0),
                                VertexAttribute(format: .float32x2, offset: 4 * floatSize, shaderLocation: 1),
                                VertexAttribute(format: .float32x2, offset: 6 * floatSize, shaderLocation: 2),
                                VertexAttribute(format: .float32x4, offset: 8 * floatSize, shaderLocation: 3),
                                VertexAttribute(format: .float32x4, offset: 12 * floatSize, shaderLocation: 4),
                            ])
                    ]),
                primitive: PrimitiveState(topology: .triangleStrip),
                fragment: FragmentState(
                    module: shaderModule, entryPoint: "fragmentMain",
                    targets: [ColorTargetState(format: format, blend: .alphaBlending)])))
    }

    // Starts a frame, forgetting the runs the last one did not draw, and the
    // glyphs if the atlas ran out of room.
    func begin() {
        instances.removeAll(keepingCapacity: true)
        customDraws.removeAll(keepingCapacity: true)
        previousRuns = runs
        runs = [:]
        if atlasIsFull {
            glyphs = [:]
            shelf = (0, 0, 0)
            atlasIsFull = false
        }
    }

    // `text` shaped at `points` to the em.
    func run(_ text: String, points: Float) -> ShapedRun {
        let key = RunKey(text: text, pixelSize: UInt32((points * scale).rounded()))
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

    // `text` shaped at `points` to the em, in lines no wider than `width`
    // points, if there is a width, broken where `lineBreaks` allows, and at
    // its newlines.
    func lines(_ text: String, points: Float, width: Float?) -> [ShapedRun] {
        let paragraph = run(text, points: points)
        let maximum = width.map { Int(($0 * scale * 64).rounded(.down)) }
        let bytes = Array(text.utf8)
        return wrap(text, clusters: paragraph.clusters, width: paragraph.width, maximum: maximum).map {
            run(String(decoding: bytes[$0], as: UTF8.self), points: points)
        }
    }

    // Has `run` drawn with its top-left corner at `x`, `y` in points, in
    // `color`, which is not premultiplied.
    func draw(_ run: ShapedRun, x: Float, y: Float, color: Color) throws {
        let left = Int((x * scale).rounded())
        let baseline = Int((y * scale).rounded()) + run.ascender
        for (key, glyphX, glyphY) in run.glyphs {
            guard let glyph = try glyph(key), glyph.width > 0, glyph.height > 0 else { continue }
            instances += [
                Float(left + (glyphX + 32) >> 6 + glyph.left), Float(baseline - (glyphY + 32) >> 6 - glyph.top),
                Float(glyph.width), Float(glyph.height),
                Float(glyph.x), Float(glyph.y), Float(glyph.width), Float(glyph.height),
                Float(color.r), Float(color.g), Float(color.b), Float(color.a),
            ] + clipInPixels
        }
    }

    // Has a rectangle filled, from `x`, `y` in points, `width` by `height`,
    // in `color`, which is not premultiplied, on whole pixels.
    func fill(x: Float, y: Float, width: Float, height: Float, color: Color) {
        let left = (x * scale).rounded()
        let top = (y * scale).rounded()
        let white = Float(Self.atlasSize - 1) + 0.5
        instances += [
            left, top, ((x + width) * scale).rounded() - left, ((y + height) * scale).rounded() - top,
            white, white, 0, 0,
            Float(color.r), Float(color.g), Float(color.b), Float(color.a),
        ] + clipInPixels
    }

    // Draws recorded with WebGPU by others, each after the instances before
    // it, and before those after it.
    private var customDraws: [(instance: Int, draw: (RenderPassEncoder, Float, Float) throws -> Void)] = []

    /// Has `draw` record its own drawing into the frame's render pass, which
    /// it is given with the screen's width and height in pixels, over what is
    /// drawn before it and under what is drawn after it. It may set the pass's
    /// pipeline, bind groups, buffers, viewport and scissor rectangle, which
    /// are set back after it.
    func drawCustom(_ draw: @escaping (RenderPassEncoder, Float, Float) throws -> Void) {
        customDraws.append((instances.count / Self.floatsPerInstance, draw))
    }

    // Records the frame's text and rectangles into `pass`, and the custom
    // draws among them, over a screen `width` by `height` pixels.
    func end(into pass: RenderPassEncoder, width: UInt32, height: UInt32) throws {
        let queue = device.getQueue()
        let count = instances.count / Self.floatsPerInstance
        if count > 0 {
            [Float(width), Float(height)].withUnsafeBytes { queue.writeBuffer(screen, bufferOffset: 0, data: $0) }
            let byteCount = UInt64(instances.count * MemoryLayout<Float>.stride)
            if byteCount > instanceBufferSize {
                var size = max(instanceBufferSize, 4096)
                while size < byteCount { size *= 2 }
                instanceBuffer = try device.createBuffer(
                    descriptor: BufferDescriptor(label: "glyphs", usage: [.vertex, .copyDst], size: size))
                instanceBufferSize = size
            }
            instances.withUnsafeBytes { queue.writeBuffer(instanceBuffer!, bufferOffset: 0, data: $0) }
        }

        func drawInstances(_ range: Range<Int>) {
            guard !range.isEmpty else { return }
            pass.setPipeline(pipeline)
            pass.setBindGroup(groupIndex: 0, group: bindGroup)
            pass.setVertexBuffer(
                slot: 0, buffer: instanceBuffer!, offset: 0,
                size: UInt64(count * Self.floatsPerInstance * MemoryLayout<Float>.stride))
            pass.draw(
                vertexCount: 4, instanceCount: UInt32(range.count), firstVertex: 0, firstInstance: UInt32(range.lowerBound))
        }
        var drawn = 0
        for (instance, draw) in customDraws {
            drawInstances(drawn..<instance)
            drawn = instance
            try draw(pass, Float(width), Float(height))
            pass.setViewport(x: 0, y: 0, width: Float(width), height: Float(height), minDepth: 0, maxDepth: 1)
            pass.setScissorRect(x: 0, y: 0, width: width, height: height)
        }
        drawInstances(drawn..<count)
    }

    // The glyph in the atlas, which it is rasterized into the first time,
    // or nil if the atlas has no room left for it this frame.
    private func glyph(_ key: GlyphKey) throws -> AtlasGlyph? {
        if let glyph = glyphs[key] { return glyph }
        guard !atlasIsFull else { return nil }
        setFacePixelSize(key.pixelSize)
        try loadGlyph(face: face, glyphIndex: key.index, loadFlags: [.render, .targetLight])
        let bitmap = face.glyph.bitmap
        let (width, height) = (Int(bitmap.width), Int(bitmap.rows))

        // Left to right along the shelf, a texel apart, and on a new shelf
        // below when this one is full.
        if shelf.x + width > Self.atlasSize {
            shelf = (0, shelf.y + shelf.height + 1, 0)
        }
        // The last row has the white texel.
        guard shelf.y + height < Self.atlasSize - 1 else {
            atlasIsFull = true
            return nil
        }
        let glyph = AtlasGlyph(
            x: shelf.x, y: shelf.y, width: width, height: height, left: Int(face.glyph.bitmapLeft),
            top: Int(face.glyph.bitmapTop))
        shelf = (shelf.x + width + 1, shelf.y, max(shelf.height, height))
        if width > 0, height > 0 {
            bitmap.buffer.withUnsafeBytes { data in
                device.getQueue().writeTexture(
                    destination: TexelCopyTextureInfo(
                        texture: atlas, origin: Origin3D(x: UInt32(glyph.x), y: UInt32(glyph.y))),
                    data: data,
                    dataLayout: TexelCopyBufferLayout(bytesPerRow: UInt32(bitmap.pitch), rowsPerImage: UInt32(height)),
                    writeSize: Extent3D(width: UInt32(width), height: UInt32(height), depthOrArrayLayers: 1))
            }
        }
        glyphs[key] = glyph
        return glyph
    }

    private func setFacePixelSize(_ pixelSize: UInt32) {
        guard pixelSize != facePixelSize else { return }
        try? setPixelSizes(face: face, pixelWidth: 0, pixelHeight: pixelSize)
        facePixelSize = pixelSize
    }
}
