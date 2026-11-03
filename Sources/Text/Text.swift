import Dawn
import FreeType
import GameToolkit
import HarfBuzz
@_spi(ExperimentalCustomExecutors) import MainLoop
import SDL3
import SDL3Dawn

@main
struct Text: AsyncMain {
    static func run() async throws {
        let system = try `init`(flags: [.video])
        defer { withExtendedLifetime(system) {} }
        let window = try createWindow(title: "text", w: 640, h: 360, flags: platformWindowFlags([.highPixelDensity]))

        let instance = try createInstance()
        let surface = try instance.createSurface(from: window)
        let adapter = try await instance.requestAdapter(options: platformAdapterOptions())
        let device = try await adapter.requestDevice()
        var configuration = try configureSurface(surface, device: device, adapter: adapter, window: window)

        let font = try await readAsset("NotoSansJP-Regular.otf")
        let origin = try device.createBuffer(
            descriptor: BufferDescriptor(label: "origin", usage: [.uniform, .copyDst], size: 8))

        let shaderModule = try device.createShaderModule(
            descriptor: ShaderModuleDescriptor(
                nextInChain: ShaderSourceWGSL(
                    code: """
                        @group(0) @binding(0) var text: texture_2d<f32>;
                        @group(0) @binding(1) var<uniform> origin: vec2f;

                        // One triangle that covers the screen.
                        @vertex
                        fn vertexMain(@builtin(vertex_index) index: u32) -> @builtin(position) vec4f {
                            let corner = vec2f(f32((index << 1u) & 2u), f32(index & 2u));
                            return vec4f(corner * 2.0 - 1.0, 0.0, 1.0);
                        }

                        // The text's pixels, one to one with the screen's.
                        @fragment
                        fn fragmentMain(@builtin(position) position: vec4f) -> @location(0) vec4f {
                            let texel = vec2i(floor(position.xy - origin));
                            if (any(texel < vec2i(0)) || any(texel >= vec2i(textureDimensions(text)))) {
                                discard;
                            }
                            return vec4f(1.0, 1.0, 1.0, textureLoad(text, texel, 0).r);
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
                        binding: 1, visibility: .fragment, buffer: BufferBindingLayout(type: .uniform, minBindingSize: 8)),
                ]))
        let pipeline = try device.createRenderPipeline(
            descriptor: RenderPipelineDescriptor(
                label: "text",
                layout: try device.createPipelineLayout(
                    descriptor: PipelineLayoutDescriptor(label: "text", bindGroupLayouts: [bindGroupLayout])),
                vertex: VertexState(module: shaderModule, entryPoint: "vertexMain"),
                fragment: FragmentState(
                    module: shaderModule, entryPoint: "fragmentMain",
                    targets: [ColorTargetState(format: configuration.format, blend: .alphaBlending)])))

        // The text at 32 points to the em, in as many of the window's pixels as
        // its display has to the point.
        func makeText() throws -> (bindGroup: BindGroup, width: UInt32, height: UInt32) {
            let image = try rasterize(
                ["Hello, world!", "こんにちは、世界。"], font: font,
                pixelHeight: UInt32((32 * getWindowDisplayScale(window: window)).rounded()))
            let texture = try device.createTexture(
                descriptor: TextureDescriptor(
                    usage: [.textureBinding, .copyDst], dimension: .`2D`,
                    size: Extent3D(width: image.width, height: image.height, depthOrArrayLayers: 1), format: .r8Unorm))
            image.pixels.withUnsafeBytes { data in
                device.getQueue().writeTexture(
                    destination: TexelCopyTextureInfo(texture: texture), data: data,
                    dataLayout: TexelCopyBufferLayout(bytesPerRow: image.width, rowsPerImage: image.height),
                    writeSize: Extent3D(width: image.width, height: image.height, depthOrArrayLayers: 1))
            }
            let bindGroup = try device.createBindGroup(
                descriptor: BindGroupDescriptor(
                    label: "text", layout: bindGroupLayout,
                    entries: [
                        BindGroupEntry(binding: 0, textureView: try texture.createView()),
                        BindGroupEntry(binding: 1, buffer: origin),
                    ]))
            return (bindGroup, image.width, image.height)
        }
        var text = try makeText()

        while true {
            while let event = pollEvent() {
                if event.type == .quit || event.type == .windowCloseRequested { return }
                if event.type == .windowPixelSizeChanged {
                    configuration = (try? configureSurface(surface, device: device, adapter: adapter, window: window)) ?? configuration
                }
                if event.type == .windowDisplayScaleChanged {
                    text = try makeText()
                }
            }

            // In the middle, on whole pixels.
            let center: [Float] = [
                Float((Int(configuration.width) - Int(text.width)) / 2),
                Float((Int(configuration.height) - Int(text.height)) / 2),
            ]
            center.withUnsafeBytes { device.getQueue().writeBuffer(origin, bufferOffset: 0, data: $0) }

            if let surfaceTexture = try? surface.getCurrentTexture() {
                let encoder = try device.createCommandEncoder()
                let pass = try encoder.beginRenderPass(
                    descriptor: RenderPassDescriptor(
                        colorAttachments: [
                            RenderPassColorAttachment(
                                view: try surfaceTexture.createView(), loadOp: .clear, storeOp: .store,
                                clearValue: Color(r: 0.05, g: 0.05, b: 0.08, a: 1))
                        ]))
                pass.setPipeline(pipeline)
                pass.setBindGroup(groupIndex: 0, group: text.bindGroup)
                pass.draw(vertexCount: 3, instanceCount: 1, firstVertex: 0, firstInstance: 0)
                pass.end()
                device.getQueue().submit([try encoder.finish()])
                try surface.present()
            }

            instance.processEvents()
            await nextFrame()
        }
    }

    // Lines of text in coverage from 0 to 255, shaped by HarfBuzz and
    // rasterized by FreeType at pixelHeight pixels to the em, one below another
    // the font's line height apart.
    static func rasterize(_ lines: [String], font: [UInt8], pixelHeight: UInt32) throws -> (
        pixels: [UInt8], width: UInt32, height: UInt32
    ) {
        let library = try initFreeType()
        let face = try newMemoryFace(library: library, fileBase: font)
        try setPixelSizes(face: face, pixelWidth: 0, pixelHeight: pixelHeight)
        let ascender = face.size.metrics.ascender / 64
        let lineHeight = face.size.metrics.height / 64
        let height = (lines.count - 1) * lineHeight + ascender - face.size.metrics.descender / 64

        // HarfBuzz places the glyphs in 26.6 fixed point, as FreeType measures.
        let shaper = fontCreate(face: faceCreate(blob: blobCreate(data: font), index: 0))
        fontSetScale(font: shaper, xScale: Int32(pixelHeight) * 64, yScale: Int32(pixelHeight) * 64)

        var glyphs: [(bitmap: Bitmap, x: Int, y: Int)] = []
        var width = 0
        for (index, line) in lines.enumerated() {
            let buffer = bufferCreate()
            bufferAddUTF8(buffer: buffer, text: line)
            bufferGuessSegmentProperties(buffer: buffer)
            shape(font: shaper, buffer: buffer)

            let baseline = index * lineHeight + ascender
            var penX = 0
            for (info, position) in zip(bufferGetGlyphInfos(buffer: buffer), bufferGetGlyphPositions(buffer: buffer)) {
                try loadGlyph(face: face, glyphIndex: info.codepoint, loadFlags: [.render, .targetLight])
                glyphs.append(
                    (
                        face.glyph.bitmap,
                        (penX + Int(position.xOffset) + 32) >> 6 + Int(face.glyph.bitmapLeft),
                        baseline - (Int(position.yOffset) + 32) >> 6 - Int(face.glyph.bitmapTop)
                    ))
                penX += Int(position.xAdvance)
            }
            width = max(width, (penX + 32) >> 6)
        }

        var pixels = [UInt8](repeating: 0, count: width * height)
        for (bitmap, left, top) in glyphs {
            for row in 0..<Int(bitmap.rows) {
                for column in 0..<Int(bitmap.width) {
                    let (x, y) = (left + column, top + row)
                    guard (0..<width).contains(x), (0..<height).contains(y) else { continue }
                    let coverage = bitmap.buffer[row * Int(bitmap.pitch) + column]
                    pixels[y * width + x] = max(pixels[y * width + x], coverage)
                }
            }
        }
        return (pixels, UInt32(width), UInt32(height))
    }
}
